#!/usr/bin/env python3
"""Record a running macOS app's complete process-group memory footprint."""

import argparse
import json
import math
import plistlib
import re
import statistics
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True,
                          timeout=30).stdout


def app_group(listing, bundle_id):
    """Use macOS ownership, since WebKit helpers have launchd as their parent."""
    matches = []
    for block in re.split(r'(?m)^\d+\) ', listing):
        if not re.search(r'(?m)^\s*bundleID="' + re.escape(bundle_id) + r'"\s*$', block):
            continue
        pid = re.search(r'(?m)^\s*pid = (\d+)\b', block)
        coalition = re.search(r'(?m)^\s*coalition: (\d+)(?:\s+\{([^}\n]*)\})?\s*$', block)
        path = re.search(r'(?m)^\s*bundle path="([^"]+)"', block)
        if not (pid and coalition and path):
            raise ValueError('App identity or process coalition is unavailable; no partial total is allowed.')
        members = {int(value) for value in (coalition[2] or '').split()}
        members.add(int(pid[1]))
        matches.append({'pid': int(pid[1]), 'coalition': int(coalition[1]),
                        'pids': sorted(members), 'bundle_path': path[1]})
    if len(matches) != 1:
        raise ValueError(f'Expected one running {bundle_id}; found {len(matches)}.')
    return matches[0]


def discover(bundle_id):
    return app_group(command('/usr/bin/lsappinfo', 'list'), bundle_id)


def validate_sample(payload, pids):
    if payload.get('errors') or payload.get('warnings'):
        raise ValueError('footprint reported an error or warning; inspect the raw sample.')
    measured = {process['pid'] for process in payload.get('processes', [])}
    if measured != set(pids):
        raise ValueError('The sample is missing a process or contains an unexpected process.')
    total = payload.get('total footprint')
    if payload.get('unit') != 'byte' or not isinstance(total, (int, float)) or not math.isfinite(total) or total <= 0:
        raise ValueError('Missing or invalid footprint total in bytes.')
    return total


def sample(group, path):
    args = ['/usr/bin/footprint', '--noCategories', '-j', str(path)]
    for pid in group['pids']:
        args.extend(['-p', str(pid)])
    command(*args)
    return validate_sample(json.loads(path.read_text()), group['pids'])


def verify_release_settings(path, bundle_id, bundle_path):
    """Allow an optimized build to reuse a development identity and its sessions."""
    targets = json.loads(path.read_text())
    for target in targets:
        settings = target.get('buildSettings', {})
        product = Path(settings.get('TARGET_BUILD_DIR', '')) / settings.get('FULL_PRODUCT_NAME', '')
        if settings.get('PRODUCT_BUNDLE_IDENTIFIER') != bundle_id or product.resolve() != bundle_path.resolve():
            continue
        conditions = settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '').split()
        if settings.get('CONFIGURATION') != 'Release' or settings.get('SWIFT_OPTIMIZATION_LEVEL') not in ['-O', '-Osize'] or 'DEBUG' in conditions:
            raise ValueError('Build settings do not identify an optimized Release build without DEBUG.')
        return {'configuration': settings['CONFIGURATION'],
                'swift_optimization': settings['SWIFT_OPTIMIZATION_LEVEL'],
                'compilation_conditions': conditions,
                'target': target.get('target')}
    raise ValueError('Build settings do not match the running app identity and bundle path.')


def collect(args):
    initial = discover(args.bundle_id)
    bundle_path = Path(initial['bundle_path'])
    info = plistlib.loads((bundle_path / 'Contents/Info.plist').read_bytes())
    development = 'Debug' in bundle_path.parts or args.bundle_id.endswith('.debug')
    release = verify_release_settings(args.release_build_settings, args.bundle_id, bundle_path) if args.release_build_settings else None
    if development and not release and not args.smoke_test:
        raise ValueError('Use a Release build without a debugger. --smoke-test is only for checking this tool.')

    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix=datetime.now().strftime('%Y%m%d-%H%M%S-'), dir=destination))
    metadata = {
        'schema': 1, 'started_at': datetime.now(timezone.utc).isoformat(),
        'label': args.label, 'scenario': args.scenario, 'services': args.services,
        'notes': args.notes, 'bundle_id': args.bundle_id,
        'version': info.get('CFBundleShortVersionString'), 'build': info.get('CFBundleVersion'),
        'smoke_test': args.smoke_test, 'development_identity_or_path': development,
        'verified_release_settings': release,
        'macos': command('/usr/bin/sw_vers', '-productVersion').strip(),
        'macos_build': command('/usr/bin/sw_vers', '-buildVersion').strip(),
        'model': command('/usr/sbin/sysctl', '-n', 'hw.model').strip(),
        'chip': command('/usr/sbin/sysctl', '-n', 'machdep.cpu.brand_string').strip(),
        'memory_bytes': int(command('/usr/sbin/sysctl', '-n', 'hw.memsize')),
        'power': command('/usr/bin/pmset', '-g', 'batt').strip(),
        'power_settings': command('/usr/bin/pmset', '-g', 'custom').strip(),
        'sample_count_requested': args.samples, 'interval_seconds': args.interval,
        'metric': 'macOS footprint tool aggregate total footprint in bytes',
        'status': 'incomplete', 'samples': [],
        'publication': 'Requires matched workloads, repeat runs, process review, and release-build verification.'
    }
    report = output / 'report.json'
    print(f'Recording to {output}', flush=True)
    started = time.monotonic()
    try:
        for index in range(args.samples):
            if index:
                time.sleep(max(0, started + index * args.interval - time.monotonic()))
            group = discover(args.bundle_id)
            if (group['pid'], group['coalition']) != (initial['pid'], initial['coalition']):
                raise ValueError('The app restarted during measurement; start a new run.')
            before = time.monotonic()
            total = sample(group, output / f'footprint-{index + 1:03}.json')
            after_group = discover(args.bundle_id)
            if group != after_group:
                raise ValueError('Process membership changed during a sample; let the app settle and repeat.')
            entry = {'elapsed_seconds': before - started, 'duration_seconds': time.monotonic() - before,
                     'pids': group['pids'], 'footprint_bytes': total}
            metadata['samples'].append(entry)
            print(f"{index + 1}/{args.samples}: {total / 2**20:.1f} MiB across {len(group['pids'])} processes", flush=True)
        values = [entry['footprint_bytes'] for entry in metadata['samples']]
        metadata['summary'] = {'median_bytes': statistics.median(values),
                               'minimum_bytes': min(values), 'maximum_bytes': max(values)}
        metadata['status'] = 'smoke-test-only' if args.smoke_test else 'complete-unreviewed'
    except (Exception, KeyboardInterrupt) as error:
        metadata['error'] = str(error) or 'Interrupted'
        raise
    finally:
        report.write_text(json.dumps(metadata, indent=2) + '\n')
    print(f'Saved {report}', flush=True)


def positive_number(value):
    parsed = float(value)
    if not math.isfinite(parsed) or parsed <= 0:
        raise argparse.ArgumentTypeError('Must be a finite positive number.')
    return parsed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle-id', required=True)
    parser.add_argument('--label', required=True, help='App name and run number')
    parser.add_argument('--scenario', choices=['awake', 'hibernated', 'empty', 'smoke'], required=True)
    parser.add_argument('--services', required=True, help='Service names only; do not include account identifiers')
    parser.add_argument('--notes', default='', help='Active service, settings, foreground/background, window size')
    parser.add_argument('--samples', type=int, default=31)
    parser.add_argument('--interval', type=positive_number, default=10)
    parser.add_argument('--output', type=Path, default=ROOT / '.project/benchmarks')
    parser.add_argument('--smoke-test', action='store_true')
    parser.add_argument('--release-build-settings', type=Path,
                        help='xcodebuild -showBuildSettings -json for an optimized build using a development identity')
    args = parser.parse_args()
    if args.samples < 2:
        parser.error('--samples must be at least 2')
    if (args.scenario == 'smoke') != args.smoke_test:
        parser.error('--scenario smoke and --smoke-test must be used together')
    try:
        collect(args)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f'Measurement stopped: {error}\n')


if __name__ == '__main__':
    main()
