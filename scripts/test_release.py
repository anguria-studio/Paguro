#!/usr/bin/env python3
"""Regression checks for release metadata and isolation."""
import plistlib
import unittest
from build_release import validate_app_info, ROOT, FEED, ACCOUNT


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads((ROOT / 'Configuration/DirectInfo.plist').read_bytes())
        self.info.update(CFBundleShortVersionString='0.1.0', CFBundleVersion='2',
                         CFBundleIdentifier=ACCOUNT, SUFeedURL=FEED)

    def check(self):
        validate_app_info(self.info, '0.1.0', 2, FEED, ACCOUNT)

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
        for key, value in [('CFBundleIdentifier', ACCOUNT + '.updatetest'),
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


if __name__ == '__main__':
    unittest.main()
