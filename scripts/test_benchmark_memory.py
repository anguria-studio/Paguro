#!/usr/bin/env python3
"""Check that memory comparisons cannot silently omit helper processes."""

import unittest
import json
import tempfile
from pathlib import Path
from benchmark_memory import app_group, validate_sample, verify_release_settings

LISTING = '''1) "Another app" ASN:0x0-0x1:
    bundleID="example.unrelated"
    bundle path="/Applications/Another.app"
    pid = 10 type="Foreground"
    coalition: 11 { 10 20 }
2) "Paguro" ASN:0x0-0x2:
    bundleID="studio.anguria.paguro"
    bundle path="/Applications/Paguro.app"
    pid = 100 type="Foreground"
    coalition: 22 { 100 110 120 }
3) "Paguro Web Content" ASN:0x0-0x3:
    bundleID="com.apple.WebKit.WebContent"
    pid = 110 type="UIElement"
'''


class BenchmarkMemoryTests(unittest.TestCase):
    def test_group_includes_webkit_and_excludes_unrelated_apps(self):
        self.assertEqual(app_group(LISTING, 'studio.anguria.paguro')['pids'], [100, 110, 120])

    def test_single_process_coalition(self):
        listing = LISTING.replace('22 { 100 110 120 }', '22')
        self.assertEqual(app_group(listing, 'studio.anguria.paguro')['pids'], [100])

    def test_missing_ownership_fails_instead_of_using_main_process(self):
        with self.assertRaises(ValueError):
            app_group(LISTING.replace('coalition: 22', 'unknown: 22'), 'studio.anguria.paguro')

    def test_missing_and_duplicate_apps_fail(self):
        for listing in ['', LISTING + LISTING]:
            with self.subTest(listing=listing), self.assertRaises(ValueError):
                app_group(listing, 'studio.anguria.paguro')

    def test_partial_and_failed_samples_cannot_be_reported_as_totals(self):
        payload = {'unit': 'byte', 'processes': [{'pid': 100}, {'pid': 110}], 'total footprint': 1024}
        self.assertEqual(validate_sample(payload, [100, 110]), 1024)
        for overrides, pids in [({}, [100, 110, 120]), ({'errors': ['denied']}, [100, 110]),
                                ({'warnings': ['partial']}, [100, 110]), ({'unit': 'MiB'}, [100, 110]),
                                ({'total footprint': float('nan')}, [100, 110])]:
            with self.subTest(overrides=overrides, pids=pids), self.assertRaises(ValueError):
                validate_sample({**payload, **overrides}, pids)

    def test_release_proof_must_match_the_running_product_and_optimization(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'settings.json'
            bundle = Path(directory) / 'Release/Paguro.app'
            settings = {'CONFIGURATION': 'Release', 'SWIFT_OPTIMIZATION_LEVEL': '-O',
                        'PRODUCT_BUNDLE_IDENTIFIER': 'studio.anguria.paguro.debug',
                        'TARGET_BUILD_DIR': str(bundle.parent), 'FULL_PRODUCT_NAME': bundle.name}
            path.write_text(json.dumps([{'target': 'Paguro', 'buildSettings': settings}]))
            self.assertEqual(verify_release_settings(path, settings['PRODUCT_BUNDLE_IDENTIFIER'], bundle)['swift_optimization'], '-O')
            for override in [{'CONFIGURATION': 'Debug'}, {'SWIFT_OPTIMIZATION_LEVEL': '-Onone'},
                             {'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG'}, {'FULL_PRODUCT_NAME': 'Different.app'}]:
                path.write_text(json.dumps([{'buildSettings': {**settings, **override}}]))
                with self.subTest(override=override), self.assertRaises(ValueError):
                    verify_release_settings(path, settings['PRODUCT_BUNDLE_IDENTIFIER'], bundle)


if __name__ == '__main__':
    unittest.main()
