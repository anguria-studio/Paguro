#!/usr/bin/env python3
"""Regression checks for release metadata and isolation."""
import plistlib
import unittest
import tempfile
from pathlib import Path
from build_release import (validate_app_info, ROOT, FEED, BUNDLE_ID, ACCOUNT, notary_profile,
                           DEBUG_ONLY_MARKERS, check_debug_markers, debug_markers,
                           STABLE_DMG_NAME, add_stable_download, homebrew_cask)


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads((ROOT / 'Configuration/DirectInfo.plist').read_bytes())
        self.info.update(CFBundleShortVersionString='0.1.0', CFBundleVersion='2',
                         CFBundleIdentifier=BUNDLE_ID, SUFeedURL=FEED)

    def check(self):
        validate_app_info(self.info, '0.1.0', 2, FEED, BUNDLE_ID)

    def test_keychain_label_is_not_a_bundle_identity(self):
        self.assertNotEqual(BUNDLE_ID, ACCOUNT)
        self.info['CFBundleIdentifier'] = ACCOUNT
        with self.assertRaises(ValueError):
            self.check()

    def test_notary_profile_precedence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'release-config.json'
            self.assertEqual(notary_profile({}, path), 'paguro')
            path.write_text('{"notary_profile": "shared-apple-account"}')
            self.assertEqual(notary_profile({}, path), 'shared-apple-account')
            self.assertEqual(notary_profile({'PAGURO_NOTARY_PROFILE': 'override'}, path), 'override')
            path.write_text('{"notary_profile": ""}')
            with self.assertRaises(ValueError):
                notary_profile({}, path)

    def test_valid_release(self):
        self.check()

    def test_rejects_unsigned_feed_and_archive(self):
        for key in ['SURequireSignedFeed', 'SUVerifyUpdateBeforeExtraction']:
            with self.subTest(key=key):
                original = self.info[key]
                self.info[key] = False
                with self.assertRaises(ValueError):
                    self.check()
                self.info[key] = original

    def test_rejects_test_identity_and_feed(self):
        for key, value in [('CFBundleIdentifier', BUNDLE_ID + '.updatetest'),
                           ('SUFeedURL', 'http://127.0.0.1:8765/appcast.xml'),
                           ('CFBundleVersion', '1')]:
            with self.subTest(key=key):
                original = self.info[key]
                self.info[key] = value
                with self.assertRaises(ValueError):
                    self.check()
                self.info[key] = original

    def test_normal_project_has_no_update_configuration(self):
        normal = plistlib.loads((ROOT / 'Paguro/Info.plist').read_bytes())
        self.assertFalse(any(key.startswith('SU') for key in normal))
        self.assertNotIn('Sparkle', (ROOT / 'project.yml').read_text())


class DebugMarkerTests(unittest.TestCase):
    def test_finds_each_debug_only_marker_in_binary_bytes(self):
        for marker in DEBUG_ONLY_MARKERS:
            with self.subTest(marker=marker):
                data = b'\xcf\xfa\xed\xfe binary noise ' + marker.encode() + b'\x00more'
                self.assertEqual(debug_markers(data), [marker])

    def test_accepts_bytes_without_a_marker(self):
        # The screen preset argument stays out of the list: released builds
        # already drop that text, so a match would report an accepted string.
        self.assertEqual(debug_markers(b'\xcf\xfa\xed\xfe --paguro-island-screen\x00'), [])

    def test_scan_names_the_marker_and_passes_a_clean_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Paguro'
            path.write_bytes(b'\xcf\xfa\xed\xfe' + DEBUG_ONLY_MARKERS[0].encode())
            with self.assertRaises(RuntimeError) as failure:
                check_debug_markers(path)
            self.assertIn(DEBUG_ONLY_MARKERS[0], str(failure.exception))
            path.write_bytes(b'\xcf\xfa\xed\xfe release only')
            check_debug_markers(path)

    def test_scan_reads_every_mach_o_file_in_an_app_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Paguro.app'
            (app / 'Contents/MacOS').mkdir(parents=True)
            (app / 'Contents/MacOS/Paguro').write_bytes(b'\xcf\xfa\xed\xfe release only')
            (app / 'Contents/Resources').mkdir()
            (app / 'Contents/Resources/notes.txt').write_text(DEBUG_ONLY_MARKERS[3])
            check_debug_markers(app)
            (app / 'Contents/MacOS/Helper').write_bytes(
                b'\xca\xfe\xba\xbe' + DEBUG_ONLY_MARKERS[1].encode())
            with self.assertRaises(RuntimeError) as failure:
                check_debug_markers(app)
            self.assertIn(DEBUG_ONLY_MARKERS[1], str(failure.exception))

    def test_scan_requires_a_mach_o_file(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(RuntimeError):
                check_debug_markers(Path(directory))



class StableDownloadTests(unittest.TestCase):
    def test_copy_has_the_fixed_name_and_the_same_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / 'Paguro-9.9.9-99.dmg'
            dmg.write_bytes(b'disk image bytes')
            stable = add_stable_download(dmg)
            self.assertEqual(stable.name, STABLE_DMG_NAME)
            self.assertEqual(stable.parent, dmg.parent)
            self.assertEqual(stable.read_bytes(), dmg.read_bytes())
            self.assertTrue(dmg.exists())

    def test_fixed_name_matches_the_public_download_address(self):
        # The website links to /releases/latest/download/Paguro.dmg.
        self.assertEqual(STABLE_DMG_NAME, 'Paguro.dmg')

    def test_refuses_to_replace_an_existing_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / 'Paguro-9.9.9-99.dmg'
            dmg.write_bytes(b'new')
            (Path(directory) / STABLE_DMG_NAME).write_bytes(b'old')
            with self.assertRaises(RuntimeError):
                add_stable_download(dmg)



class HomebrewCaskTests(unittest.TestCase):
    PUBLISHED = '''cask "paguro" do
  version "1.0.5,14"
  sha256 "1be75ec2e2be4e21347a7717b22ca2d6aed9d8ad40b7c0feda171fa770f0988d"

  url "https://github.com/anguria-studio/Paguro/releases/download/v#{version.csv.first}/Paguro-#{version.csv.first}-#{version.csv.second}.dmg"
  name "Paguro"
  desc "Native workspace for web apps"
  homepage "https://anguria.studio/paguro"

  livecheck do
    url "https://github.com/anguria-studio/Paguro/releases/latest/download/appcast.xml"
    strategy :sparkle do |item|
      "#{item.short_version},#{item.version}"
    end
  end

  auto_updates true
  depends_on macos: :sequoia

  app "Paguro.app"

  zap trash: [
    "~/Library/Application Scripts/studio.anguria.paguro",
    "~/Library/Containers/studio.anguria.paguro",
  ]
end
'''

    def test_matches_the_cask_published_for_1_0_5(self):
        # The tap passed brew style and brew audit --strict --online with this text.
        sha = '1be75ec2e2be4e21347a7717b22ca2d6aed9d8ad40b7c0feda171fa770f0988d'
        self.assertEqual(homebrew_cask('1.0.5', 14, sha), self.PUBLISHED)

    def test_only_the_version_and_the_hash_change(self):
        first = homebrew_cask('1.0.5', 14, 'a' * 64).splitlines()
        second = homebrew_cask('1.0.6', 15, 'b' * 64).splitlines()
        changed = [i for i, (x, y) in enumerate(zip(first, second)) if x != y]
        self.assertEqual(changed, [1, 2])
        self.assertIn('version "1.0.6,15"', second[1])


if __name__ == '__main__':
    unittest.main()
