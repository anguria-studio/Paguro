import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from measure_extension_memory import parse_marker, summarize  # noqa: E402

MIB = 1024 * 1024


class MeasureExtensionMemoryTests(unittest.TestCase):
    def test_parses_only_measurement_markers(self):
        self.assertEqual(parse_marker('EXTENSION-MEMORY ready phase=darkreader services=5'),
                         ('ready', 'darkreader', 5))
        self.assertEqual(parse_marker('x EXTENSION-MEMORY idle phase=baseline services=1\n'),
                         ('idle', 'baseline', 1))
        self.assertIsNone(parse_marker('EXTENSION-MEMORY done phase=darkreader services=5'))
        self.assertIsNone(parse_marker('EXTENSION-MEMORY package slug=darkreader version=1 sha256=' + 'a' * 64))

    def test_phase_cost_counts_only_processes_that_the_phase_started(self):
        existing = {'1': {'name': 'service', 'bytes': 500 * MIB}}
        samples = [
            {'kind': 'idle', 'phase': 'baseline', 'services': 5, 'processes': existing},
            {'kind': 'ready', 'phase': 'baseline', 'services': 5, 'processes': {
                '1': {'name': 'service', 'bytes': 900 * MIB},
                '2': {'name': 'view', 'bytes': 30 * MIB}}},
            {'kind': 'idle', 'phase': 'darkreader', 'services': 5, 'processes': existing},
            {'kind': 'ready', 'phase': 'darkreader', 'services': 5, 'processes': {
                '1': {'name': 'service', 'bytes': 100 * MIB},
                '3': {'name': 'view', 'bytes': 30 * MIB},
                '4': {'name': 'background', 'bytes': 200 * MIB}}},
        ]
        table = {row['phase']: row for row in summarize(samples)}
        self.assertEqual(table['baseline']['phase_bytes'], 30 * MIB)
        self.assertEqual(table['baseline']['new_processes'], 1)
        self.assertIsNone(table['baseline']['extension_bytes'])
        self.assertEqual(table['darkreader']['phase_bytes'], 230 * MIB)
        self.assertEqual(table['darkreader']['extension_bytes'], 200 * MIB)
        self.assertEqual(table['darkreader']['extension_bytes_per_service'], 40 * MIB)

    def test_a_taken_prewarmed_process_counts_its_growth(self):
        samples = [
            {'kind': 'idle', 'phase': 'baseline', 'services': 1, 'processes': {
                '1': {'name': 'com.apple.WebKit.WebContent', 'bytes': 10 * MIB},
                '2': {'name': 'com.apple.WebKit.WebContent', 'bytes': 400 * MIB}}},
            {'kind': 'ready', 'phase': 'baseline', 'services': 1, 'processes': {
                '1': {'name': 'com.apple.WebKit.WebContent', 'bytes': 40 * MIB},
                '2': {'name': 'com.apple.WebKit.WebContent', 'bytes': 600 * MIB}}},
        ]
        row = summarize(samples)[0]
        self.assertEqual(row['phase_bytes'], 30 * MIB)
        self.assertEqual(row['new_processes'], 1)

    def test_incomplete_phase_is_left_out(self):
        samples = [{'kind': 'idle', 'phase': 'darkreader', 'services': 1, 'processes': {}}]
        self.assertEqual(summarize(samples), [])


if __name__ == '__main__':
    unittest.main()
