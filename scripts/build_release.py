#!/usr/bin/env python3
"""Build a signed, notarized direct release. Never publishes or exports keys."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = 'studio.anguria.paguro'
# Preserve the existing signing key; its Keychain label is not an app identity.
ACCOUNT = 'com.tommasolaterza.Paguro'
REPOSITORY = 'anguria-studio/Paguro'
FEED = f'https://github.com/{REPOSITORY}/releases/latest/download/appcast.xml'


def run(*args, capture=False):
    return subprocess.run([str(a) for a in args], check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def validate_app_info(info, version, build, feed, bundle_id):
    expected = {
        'CFBundleShortVersionString': version,
        'CFBundleVersion': str(build),
        'CFBundleIdentifier': bundle_id,
        'SUFeedURL': feed,
        'SUEnableInstallerLauncherService': True,
        'SURequireSignedFeed': True,
        'SUVerifyUpdateBeforeExtraction': True,
        'SUSendProfileInfo': False,
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f'Unexpected release setting: {key}')
    if info.get('SUEnableDownloaderService', False):
        raise ValueError('Downloader service must remain disabled')


def notary_profile(environ, config_path):
    override = environ.get('PAGURO_NOTARY_PROFILE')
    if override:
        return override
    if config_path.exists():
        profile = json.loads(config_path.read_text()).get('notary_profile')
        if not isinstance(profile, str) or not profile.strip():
            raise ValueError('Local release configuration requires a notary_profile')
        return profile
    return 'paguro'


def notarize(path, profile):
    result = json.loads(run('xcrun', 'notarytool', 'submit', path,
                           '--keychain-profile', profile, '--wait',
                           '--output-format', 'json', capture=True))
    if result.get('status') != 'Accepted':
        raise RuntimeError(f'Notarization rejected {path.name}: {result.get("id")}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True, type=int)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--sparkle-tools', required=True, type=Path,
                        help='bin directory from the pinned Sparkle distribution')
    parser.add_argument('--test-feed', help='Loopback feed for an isolated update test')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version) or args.build < 1:
        parser.error('Use a three-part version and a positive build number')
    if args.test_feed and not re.fullmatch(r'http://127\.0\.0\.1:\d+/appcast\.xml', args.test_feed):
        parser.error('Test feed must use http://127.0.0.1:PORT/appcast.xml')
    output = args.output.resolve()
    if output.exists():
        parser.error('Output directory must not exist; preserve previous release artifacts')
    tools = args.sparkle_tools.resolve()
    public_key = run(tools / 'generate_keys', '--account', ACCOUNT, '-p', capture=True).strip()
    info = plistlib.loads((ROOT / 'Configuration/DirectInfo.plist').read_bytes())
    if public_key != info['SUPublicEDKey']:
        raise RuntimeError('Keychain public key does not match the app configuration')
    identities = run('security', 'find-identity', '-v', '-p', 'codesigning', capture=True)
    match = re.search(r'"(Developer ID Application: [^"\n]+ \(([A-Z0-9]+)\))"', identities)
    if not match:
        raise RuntimeError('A Developer ID Application identity is required')
    identity, team = match.groups()
    profile = notary_profile(os.environ, ROOT / '.project/release-config.json')
    run('xcrun', 'notarytool', 'history', '--keychain-profile', profile, capture=True)
    output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix='paguro-release-') as temporary:
        work = Path(temporary)
        project = work / 'project'
        project.mkdir()
        # XcodeGen source groups remain relative to the generated project.
        for name in ("Paguro", "PaguroTests", "Core", "Configuration", "licenses",
                     "LICENSE", "THIRD_PARTY_NOTICES.md"):
            (project / name).symlink_to(ROOT / name, target_is_directory=(ROOT / name).is_dir())
        run('xcodegen', 'generate', '--spec', ROOT / 'project-direct.yml', '--project', project)
        archive = output / 'Paguro.xcarchive'
        settings = [f'SRCROOT={ROOT}', f'CODE_SIGN_IDENTITY={identity}', f'DEVELOPMENT_TEAM={team}',
                    'CODE_SIGN_STYLE=Manual', 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO',
                    'OTHER_CODE_SIGN_FLAGS=--timestamp', 'ARCHS=arm64 x86_64',
                    'ONLY_ACTIVE_ARCH=NO',
                    f'CODE_SIGN_ENTITLEMENTS={ROOT / "Configuration/Direct.entitlements"}',
                    f'INFOPLIST_FILE={ROOT / "Configuration/DirectInfo.plist"}',
                    f'MARKETING_VERSION={args.version}',
                    f'CURRENT_PROJECT_VERSION={args.build}']
        if args.test_feed:
            # A separate identity prevents the update test from using real services.
            info['SUFeedURL'] = args.test_feed
            info['NSAppTransportSecurity'] = {'NSAllowsLocalNetworking': True}
            test_info = work / 'TestInfo.plist'
            test_info.write_bytes(plistlib.dumps(info))
            settings += [f'INFOPLIST_FILE={test_info}',
                         f'PRODUCT_BUNDLE_IDENTIFIER={BUNDLE_ID}.updatetest']
        run('xcodebuild', '-project', project / 'Paguro.xcodeproj', '-scheme', 'Paguro',
            '-configuration', 'Release', '-destination', 'generic/platform=macOS',
            '-archivePath', archive, *settings, 'archive')
        export_options = work / 'ExportOptions.plist'
        export_options.write_bytes(plistlib.dumps(dict(method='developer-id', teamID=team,
            signingStyle='manual', signingCertificate=identity, stripSwiftSymbols=True)))
        exported = output / 'app'
        run('xcodebuild', '-exportArchive', '-archivePath', archive,
            '-exportPath', exported, '-exportOptionsPlist', export_options)
        app = exported / 'Paguro.app'
        exported_info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        if exported_info.get('SUPublicEDKey') != public_key:
            raise RuntimeError('Exported update key differs from the signing key')
        validate_app_info(exported_info,
                          args.version, args.build, args.test_feed or FEED,
                          BUNDLE_ID + '.updatetest' if args.test_feed else BUNDLE_ID)
        entitlements = plistlib.loads(run('codesign', '-d', '--entitlements', '-',
                                         '--xml', app, capture=True).encode())
        if entitlements.get('com.apple.security.get-task-allow', False):
            raise RuntimeError('Export contains a debug entitlement')
        if not entitlements.get('com.apple.security.app-sandbox', False):
            raise RuntimeError('Export lost its sandbox entitlement')
        run('codesign', '--verify', '--deep', '--strict', app)
        run('lipo', app / 'Contents/MacOS/Paguro', '-verify_arch', 'arm64', 'x86_64')
        app_zip = work / 'Paguro.zip'
        run('ditto', '-c', '-k', '--keepParent', app, app_zip)
        notarize(app_zip, profile)
        run('xcrun', 'stapler', 'staple', app)
        run('xcrun', 'stapler', 'validate', app)
        run('spctl', '--assess', '--type', 'execute', app)
        stage = work / 'stage'
        stage.mkdir()
        run('ditto', app, stage / 'Paguro.app')
        (stage / 'Applications').symlink_to('/Applications')
        assets = output / 'assets'
        assets.mkdir()
        suffix = '-updatetest' if args.test_feed else ''
        dmg = assets / f'Paguro-{args.version}-{args.build}{suffix}.dmg'
        run('hdiutil', 'create', '-volname', 'Paguro', '-srcfolder', stage,
            '-format', 'UDZO', dmg)
        run('codesign', '--sign', identity, '--timestamp', dmg)
        notarize(dmg, profile)
        run('xcrun', 'stapler', 'staple', dmg)
        run('xcrun', 'stapler', 'validate', dmg)
        download_url = (args.test_feed.rsplit('/', 1)[0] + '/' if args.test_feed else
                        f'https://github.com/{REPOSITORY}/releases/download/v{args.version}/')
        run(tools / 'generate_appcast', '--account', ACCOUNT, '--download-url-prefix',
            download_url, '--maximum-deltas', '0', assets)
        run(tools / 'sign_update', '--account', ACCOUNT, '--verify', assets / 'appcast.xml')
        checksums = ''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n'
                            for p in sorted(assets.iterdir()) if p.is_file())
        (assets / 'SHA256SUMS').write_text(checksums)
        (output / 'release.json').write_text(json.dumps(dict(version=args.version,
            build=args.build, repository=REPOSITORY, feed=args.test_feed or FEED,
            test_only=bool(args.test_feed), source_commit=run('git', '-C', ROOT,
            'rev-parse', 'HEAD', capture=True).strip(), source_dirty=bool(run('git',
            '-C', ROOT, 'status', '--porcelain', capture=True).strip())), indent=2)+'\n')
    print(f'Verified local release: {output}. Nothing was published.', flush=True)


if __name__ == '__main__':
    main()
