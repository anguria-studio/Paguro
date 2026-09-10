#!/usr/bin/env python3
"""Check that a session summary cannot overstate, mismatch, or cherry-pick a result."""

import argparse
import json
import tempfile
import unittest
from pathlib import Path
from benchmark_summary import MIB, NO_CLAIM, UNREVIEWED, Refusal, build, mib

SERVICES = 'Slack, WhatsApp Web, Gmail, Telegram, Discord'
SAMPLE_COUNT = 31
AC_POWER = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1234)\t100%; charged; present: true"
BATTERY_POWER = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1234)\t82%; discharging; 5:12 remaining"
CLEAN = [(400, 1000), (402, 1005), (404, 1010), (406, 1015), (390, 1020)]


def write_report(directory, app, number, median_mib, started, power=AC_POWER, **overrides):
    """One realistic per-run report, with a flat sample series whose median is exact."""
    paguro = app == 'Paguro'
    total = int(median_mib * MIB)
    payload = {
        'schema': 1, 'started_at': started, 'label': f'{app} awake run {number}',
        'scenario': 'awake', 'services': SERVICES, 'notes': 'Slack selected, 1440x900, foreground',
        'bundle_id': 'studio.anguria.paguro' if paguro else 'org.ferdium.ferdium-app',
        'version': '1.4.0' if paguro else '6.7.1', 'build': '204' if paguro else '6.7.1',
        'smoke_test': False, 'development_identity_or_path': paguro,
        'verified_release_settings': {'configuration': 'Release', 'swift_optimization': '-O',
                                      'compilation_conditions': [], 'target': 'Paguro'} if paguro else None,
        'macos': '15.6', 'macos_build': '24G84', 'model': 'Mac15,3',
        'chip': 'Apple M3 Pro', 'memory_bytes': 18 * 2**30,
        'power': power, 'power_settings': 'AC Power:\n sleep 0\n displaysleep 0',
        'sample_count_requested': SAMPLE_COUNT, 'interval_seconds': 10.0,
        'metric': 'macOS footprint tool aggregate total footprint in bytes',
        'status': 'complete-unreviewed',
        'samples': [{'elapsed_seconds': index * 10.0, 'duration_seconds': 0.4,
                     'pids': [100, 110, 120], 'footprint_bytes': total} for index in range(SAMPLE_COUNT)],
        'summary': {'median_bytes': total, 'minimum_bytes': total, 'maximum_bytes': total},
        'error': None,
        'publication': 'Requires matched workloads, repeat runs, process review, and release-build verification.',
    }
    payload.update(overrides)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'report.json').write_text(json.dumps(payload, indent=2) + '\n')
    return payload


def write_session(root, pairs, overrides=None, power=AC_POWER, swap=None, unstarted=0):
    """N matched pairs in alternating order, plus the manifest that points at them.

    `unstarted` appends that many planned-but-never-launched entries, as an aborted session records them:
    no run directory, no report on disk.
    """
    overrides = overrides or {}
    runs, clock = [], 0
    for pair, values in enumerate(pairs, start=1):
        order = list(zip(['Paguro', 'Ferdium'], values))
        if pair % 2 == 0:
            order.reverse()
        for position, (app, median_mib) in enumerate(order, start=1):
            clock += 1
            directory = root / f'{app.lower()}-{pair}'
            report = write_report(directory, app, pair, median_mib, f'2026-09-10T10:{clock:02}:00+00:00',
                                  **{'power': power, **overrides.get((app, pair), {})})
            runs.append({'pair': pair, 'order': position, 'app': app, 'bundle_id': report['bundle_id'],
                         'label': report['label'], 'run_dir': str(directory),
                         'status': report['status'], 'error': None})
    for index in range(unstarted):
        pair = len(pairs) + 1 + index // 2
        app = 'Paguro' if index % 2 == 0 else 'Ferdium'
        runs.append({'pair': pair, 'order': index % 2 + 1, 'app': app,
                     'bundle_id': 'studio.anguria.paguro' if app == 'Paguro' else 'org.ferdium.ferdium-app',
                     'label': f'{app} awake run {pair}', 'run_dir': None,
                     'status': 'not-started', 'error': None})
    environment = {'macos': '15.6', 'model': 'Mac15,3', 'power_start': power, 'power_end': power}
    if swap is not None:
        environment.update({'swap_used_mib_start': swap[0], 'swap_used_mib_end': swap[1]})
    manifest = {
        'schema': 1, 'scenario': 'awake', 'pairs_requested': len(pairs), 'services': SERVICES,
        'first': 'paguro', 'started_at': '2026-09-10T10:00:00+00:00',
        'finished_at': '2026-09-10T11:30:00+00:00', 'status': 'complete', 'error': None,
        'environment': environment,
        'paguro': {'app_path': '/Applications/Paguro.app', 'bundle_id': 'studio.anguria.paguro',
                   'release_build_settings': str(root / 'settings.json')},
        'ferdium': {'bundle_id': 'org.ferdium.ferdium-app'},
        'runs': runs,
    }
    path = root / 'manifest.json'
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    return path


def summarize(**options):
    defaults = {'manifest': None, 'reports': None, 'format': 'md', 'write': None,
                'include_incomplete': False, 'reviewed': False}
    return build(argparse.Namespace(**{**defaults, **options}))


class BenchmarkSummaryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)

    def session(self, pairs=CLEAN, **kwargs):
        return write_session(self.root, pairs, **kwargs)

    def test_mib_conversion_and_one_decimal_rounding(self):
        self.assertEqual([mib(MIB), mib(MIB * 3 // 2), mib(int(100.06 * MIB))], [1.0, 1.5, 100.1])
        result, text = summarize(manifest=self.session())
        self.assertEqual(result['pairs'][0]['paguro_bytes'], 400 * MIB)
        self.assertEqual(result['pairs'][0]['paguro_mib'], 400.0)
        self.assertIn('| 1 | 400.0 | 1000.0 | 60.0 |', text)

    def test_reduction_arithmetic_on_known_medians(self):
        result, _ = summarize(manifest=self.session([(300, 1200), (600, 1000)]))
        self.assertEqual([pair['reduction_pct'] for pair in result['pairs']], [75.0, 40.0])
        self.assertEqual(result['reduction']['median_pct'], 57.5)
        self.assertEqual(result['reduction']['minimum_pct'], 40.0)
        self.assertEqual(result['reduction']['maximum_pct'], 75.0)
        self.assertEqual(result['apps']['Paguro']['median_mib'], 450.0)
        self.assertEqual(result['apps']['Paguro']['spread_pct'], 66.7)

    def test_clean_session_is_repeatable_and_claims_the_median(self):
        result, text = summarize(manifest=self.session())
        self.assertEqual(result['verdict'], 'repeatable')
        self.assertEqual(result['reduction']['median_pct'], 60.0)
        self.assertEqual(result['apps']['Ferdium']['spread_pct'], 2.0)
        self.assertEqual(result['claim'],
                         'Lower memory footprint than Ferdium 6.7.1 in our five-service idle test on Mac15,3, '
                         'macOS 15.6: 60.0% lower (median of 5 matched pairs).' + UNREVIEWED)
        self.assertIn('awake scenario, 5 matched pairs', text)
        self.assertNotIn(f"{result['reduction']['maximum_pct']:.1f}% lower", result['claim'])

    def test_claim_names_the_number_of_services_actually_measured(self):
        two = 'Gmail, Google Calendar'
        result, _ = summarize(manifest=self.session(overrides={
            (app, pair): {'services': two} for app in ['Paguro', 'Ferdium'] for pair in range(1, 6)}))
        self.assertIn('in our two-service idle test', result['claim'])
        self.assertNotIn('five-service', result['claim'])
        eight = ', '.join(['A'] * 8)
        result, _ = summarize(manifest=self.session(overrides={
            (app, pair): {'services': eight} for app in ['Paguro', 'Ferdium'] for pair in range(1, 6)}))
        self.assertIn('in our eight-service idle test', result['claim'])

    def test_a_pair_without_an_advantage_is_inconclusive(self):
        pairs = list(CLEAN)
        pairs[2] = (1010, 1010)
        result, text = summarize(manifest=self.session(pairs))
        self.assertEqual(result['pairs'][2]['reduction_pct'], 0.0)
        self.assertEqual(result['verdict'], 'mixed or inconclusive')
        self.assertEqual(result['claim'], NO_CLAIM)
        self.assertIn(NO_CLAIM, text)

    def test_median_reduction_inside_the_run_to_run_spread_is_inconclusive(self):
        result, _ = summarize(manifest=self.session([(300, 1200), (600, 1000)]))
        self.assertTrue(all(pair['reduction_pct'] > 0 for pair in result['pairs']))
        self.assertGreater(result['reduction']['larger_spread_pct'], result['reduction']['median_pct'])
        self.assertEqual(result['verdict'], 'mixed or inconclusive')
        self.assertEqual(result['claim'], NO_CLAIM)

    def test_incomplete_runs_refuse_and_are_only_listed_with_the_flag(self):
        incomplete = {'status': 'incomplete', 'error': 'The app restarted during measurement; start a new run.'}
        manifest = self.session(overrides={('Paguro', 5): incomplete, ('Ferdium', 5): incomplete})
        with self.assertRaises(Refusal) as refused:
            summarize(manifest=manifest)
        self.assertIn('complete-unreviewed', refused.exception.reasons[0])
        result, text = summarize(manifest=manifest, include_incomplete=True)
        self.assertEqual(result['pair_count'], 4)
        self.assertEqual(len(result['excluded_runs']), 2)
        self.assertEqual(result['verdict'], 'repeatable')
        self.assertIn('## Excluded runs', text)
        self.assertNotIn('run 5', '\n'.join(run['label'] for run in result['runs']))

    def test_runs_that_never_started_refuse_and_are_only_listed_with_the_flag(self):
        manifest = self.session(unstarted=4)
        with self.assertRaises(Refusal) as refused:
            summarize(manifest=manifest)
        message = '\n'.join(refused.exception.reasons)
        self.assertEqual(len(refused.exception.reasons), 4)
        for pair in [6, 7]:
            for app in ['Paguro', 'Ferdium']:
                self.assertIn(f'{app} awake run {pair}: never started', message)
        self.assertIn('(no error recorded)', message)
        result, text = summarize(manifest=manifest, include_incomplete=True)
        self.assertEqual(result['pair_count'], len(CLEAN))
        self.assertEqual(result['verdict'], 'repeatable')
        self.assertEqual(len(result['excluded_runs']), 4)
        for run in result['excluded_runs']:
            self.assertIsNone(run['run_dir'])
            self.assertEqual(run['status'], 'not-started')
            self.assertEqual(run['reason'], 'never started (no run directory)')
        self.assertIn('## Excluded runs', text)
        self.assertIn('- Paguro: Paguro awake run 6 — (no run directory) (never started (no run directory)). '
                      'Kept and reported, never aggregated.', text)
        self.assertNotIn('run 6', '\n'.join(run['label'] for run in result['runs']))

    def test_an_unstarted_run_reports_the_error_that_ended_the_session(self):
        manifest = self.session(unstarted=1)
        payload = json.loads(manifest.read_text())
        payload['runs'][-1]['error'] = 'killed during settle, before collection'
        manifest.write_text(json.dumps(payload, indent=2) + '\n')
        with self.assertRaises(Refusal) as refused:
            summarize(manifest=manifest)
        self.assertIn('(killed during settle, before collection)', '\n'.join(refused.exception.reasons))
        result, text = summarize(manifest=manifest, include_incomplete=True)
        self.assertEqual(result['excluded_runs'][0]['reason'],
                         'never started (no run directory): killed during settle, before collection')
        self.assertIn('killed during settle, before collection', text)

    def test_json_output_carries_a_null_run_dir_for_runs_that_never_started(self):
        result, text = summarize(manifest=self.session(unstarted=2), format='json', include_incomplete=True)
        payload = json.loads(text)
        self.assertEqual(payload['pair_count'], len(CLEAN))
        self.assertEqual(len(payload['runs']), 2 * len(CLEAN))
        self.assertEqual([run['run_dir'] for run in payload['excluded_runs']], [None, None])
        self.assertIn('"run_dir": null', text)
        self.assertEqual(payload['excluded_runs'], result['excluded_runs'])

    def test_short_sample_count_is_incomplete_even_when_the_status_says_complete(self):
        short = [{'elapsed_seconds': index * 10.0, 'duration_seconds': 0.4, 'pids': [100, 110],
                  'footprint_bytes': 408 * MIB} for index in range(20)]
        manifest = self.session(overrides={('Paguro', 5): {'samples': short}})
        with self.assertRaises(Refusal) as refused:
            summarize(manifest=manifest)
        self.assertIn(f'only 20 of {SAMPLE_COUNT} requested samples', refused.exception.reasons[0])

    def test_paguro_without_release_proof_or_after_a_smoke_test_refuses(self):
        for override in [{'verified_release_settings': None}, {'smoke_test': True}]:
            with self.subTest(override=override), self.assertRaises(Refusal) as refused:
                summarize(manifest=self.session(overrides={('Paguro', 2): override}))
            self.assertRegex('\n'.join(refused.exception.reasons), 'Release|smoke test')

    def test_mismatched_versions_hardware_or_workload_refuse(self):
        cases = [(('Paguro', 3), {'version': '1.4.1'}, 'Paguro version differs'),
                 (('Ferdium', 2), {'build': '6.7.2'}, 'Ferdium build differs'),
                 (('Paguro', 1), {'services': 'Slack, Gmail'}, 'services differs'),
                 (('Ferdium', 4), {'macos': '15.7'}, 'macos differs'),
                 (('Paguro', 2), {'model': 'Mac16,1'}, 'model differs'),
                 (('Ferdium', 1), {'scenario': 'hibernated'}, 'scenario differs')]
        for target, override, expected in cases:
            with self.subTest(override=override), self.assertRaises(Refusal) as refused:
                summarize(manifest=self.session(overrides={target: override}))
            self.assertIn(expected, '\n'.join(refused.exception.reasons))

    def test_power_sources_must_match_and_an_all_battery_session_warns(self):
        with self.assertRaises(Refusal) as refused:
            summarize(manifest=self.session(overrides={('Ferdium', 3): {'power': BATTERY_POWER}}))
        self.assertIn('power sources', '\n'.join(refused.exception.reasons))
        result, text = summarize(manifest=self.session(power=BATTERY_POWER))
        self.assertEqual(len(result['warnings']), 1)
        self.assertIn('battery power', result['warnings'][0])
        self.assertIn('> **Warning:**', text)
        self.assertEqual(result['verdict'], 'repeatable')

    def test_host_swap_warns_only_above_the_threshold(self):
        result, text = summarize(manifest=self.session(swap=(10647.06, 9880.4)))
        self.assertEqual(len(result['warnings']), 1)
        self.assertIn('Host swap was 10647 MiB at session start and 9880 MiB at the end',
                      result['warnings'][0])
        self.assertIn('Treat this session as reference only', result['warnings'][0])
        self.assertIn('> **Warning:**', text)
        self.assertIn('- Host swap: 10647 MiB → 9880 MiB', text)
        self.assertEqual(result['verdict'], 'repeatable')
        result, text = summarize(manifest=self.session(swap=(120.0, 210.0)))
        self.assertEqual(result['warnings'], [])
        self.assertIn('- Host swap: 120 MiB → 210 MiB', text)

    def test_a_manifest_without_swap_fields_still_summarizes(self):
        result, text = summarize(manifest=self.session())
        self.assertEqual(result['warnings'], [])
        self.assertNotIn('Host swap', text)
        self.assertEqual(result['provenance']['swap_used_mib_start'], None)
        self.assertEqual(result['provenance']['swap_used_mib_end'], None)
        result, text = summarize(reports=sorted(self.root.glob('*-*')))
        self.assertEqual(result['warnings'], [])
        self.assertNotIn('Host swap', text)

    def test_reports_mode_infers_apps_and_pairs_from_the_reports(self):
        self.session()
        paths = sorted(self.root.glob('*-*'), reverse=True)
        result, _ = summarize(reports=paths)
        self.assertEqual(result['pair_count'], 5)
        self.assertEqual([pair['paguro_mib'] for pair in result['pairs']], [400.0, 402.0, 404.0, 406.0, 390.0])
        self.assertEqual([pair['ferdium_mib'] for pair in result['pairs']], [1000.0, 1005.0, 1010.0, 1015.0, 1020.0])
        self.assertEqual({run['app'] for run in result['runs']}, {'Paguro', 'Ferdium'})
        self.assertEqual(result['pairs'][0]['paguro_label'], 'Paguro awake run 1')

    def test_unmatched_run_counts_refuse(self):
        self.session()
        paths = [path for path in sorted(self.root.glob('*-*')) if path.name != 'ferdium-5']
        with self.assertRaises(Refusal) as refused:
            summarize(reports=paths)
        self.assertIn('Unmatched pairs', '\n'.join(refused.exception.reasons))

    def test_reviewed_only_drops_the_unreviewed_suffix(self):
        manifest = self.session()
        unreviewed, _ = summarize(manifest=manifest)
        reviewed, _ = summarize(manifest=manifest, reviewed=True)
        self.assertTrue(unreviewed['claim'].endswith(UNREVIEWED))
        self.assertEqual(unreviewed['claim'], reviewed['claim'] + UNREVIEWED)
        self.assertEqual({**unreviewed, 'claim': None, 'reviewed': None},
                         {**reviewed, 'claim': None, 'reviewed': None})

    def test_json_output_parses_and_carries_the_same_verdict(self):
        manifest = self.session()
        result, text = summarize(manifest=manifest, format='json')
        payload = json.loads(text)
        self.assertEqual(payload['verdict'], result['verdict'])
        self.assertEqual(payload['claim'], result['claim'])
        self.assertEqual(payload['pairs'][0]['reduction_pct'], 60.0)
        self.assertEqual(payload['provenance']['paguro_version'], '1.4.0')
        self.assertEqual(len(payload['runs']), 10)


if __name__ == '__main__':
    unittest.main()
