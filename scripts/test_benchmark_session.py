#!/usr/bin/env python3
"""Check that a benchmark session refuses surprises instead of measuring through them."""

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import benchmark_session

UNRELATED = '''1) "Another app" ASN:0x0-0x1:
    bundleID="example.unrelated"
    bundle path="/Applications/Another.app"
    pid = 10 type="Foreground"
    coalition: 11 { 10 20 }
'''

BLOCK = '''{index}) "{name}" ASN:0x0-0x{index}:
    bundleID="{bundle_id}"
    bundle path="{path}"
    pid = {pid} type="Foreground"
    coalition: {coalition} {{ {members} }}
'''

PAGURO_ID = 'studio.anguria.paguro.debug'
FERDIUM_ID = 'org.ferdium.ferdium-app'
AC = 'Now drawing from \'AC Power\'\n -InternalBattery-0 (id=1)\t100%; charged; 0:00 remaining present: true\n'
BATTERY = 'Now drawing from \'Battery Power\'\n -InternalBattery-0 (id=1)\t72%; discharging; 3:41 remaining present: true\n'
SWAPUSAGE = 'vm.swapusage: total = 11264.00M  used = {used:.2f}M  free = 616.94M  (encrypted)\n'


class FakeCommand:
    """Dispatch on argv[0], record every call, and never touch a real app."""

    def __init__(self, paguro_app, *, battery=False, xcode=False, running=(),
                 paguro_path=None, quits=True, collector_error=None, collector_stdout=None,
                 swap_mib=120.0, swap_output=None):
        self.calls = []
        self.paguro_app = Path(paguro_app)
        self.paguro_path = Path(paguro_path or paguro_app)
        self.power = BATTERY if battery else AC
        self.swap = SWAPUSAGE.format(used=swap_mib) if swap_output is None else swap_output
        self.xcode = xcode
        self.running = set(running)
        self.quits = quits
        self.collector_error = collector_error
        self.collector_stdout = collector_stdout
        self.run_dirs = []

    def listing(self):
        blocks = [UNRELATED]
        if self.xcode:
            blocks.append(BLOCK.format(index=2, name='Xcode', bundle_id='com.apple.dt.Xcode',
                                       path='/Applications/Xcode.app', pid=50, coalition=55,
                                       members='50'))
        if PAGURO_ID in self.running:
            blocks.append(BLOCK.format(index=3, name='Paguro', bundle_id=PAGURO_ID,
                                       path=self.paguro_path, pid=100, coalition=22,
                                       members='100 110 120'))
        if FERDIUM_ID in self.running:
            blocks.append(BLOCK.format(index=4, name='Ferdium', bundle_id=FERDIUM_ID,
                                       path='/Applications/Ferdium.app', pid=200, coalition=33,
                                       members='200 210'))
        return ''.join(blocks)

    def collect(self, args):
        if self.collector_error is not None:
            raise subprocess.CalledProcessError(1, args, output='', stderr=self.collector_error)
        if self.collector_stdout is not None:
            return self.collector_stdout
        output = Path(args[args.index('--output') + 1])
        run_dir = output / f'run-{len(self.run_dirs) + 1:03}'
        run_dir.mkdir(parents=True, exist_ok=True)
        (run_dir / 'report.json').write_text(json.dumps({'status': 'complete-unreviewed'}))
        self.run_dirs.append(run_dir)
        return f'Recording to {run_dir}\n1/3: 100.0 MiB across 3 processes\nSaved {run_dir}/report.json\n'

    def __call__(self, *args, timeout=30):
        self.calls.append(list(args))
        program = args[0]
        if program == '/usr/bin/pmset':
            return self.power
        if program == '/usr/bin/lsappinfo':
            return self.listing()
        if program == '/usr/bin/sw_vers':
            return '15.5\n'
        if program == '/usr/sbin/sysctl':
            return self.swap if 'vm.swapusage' in args else 'Mac16,6\n'
        if program == '/usr/bin/open':
            self.running.add(PAGURO_ID if args[1] == '-n' else args[2])
            return ''
        if program == '/usr/bin/osascript':
            if self.quits:
                self.running -= {identifier for identifier in [PAGURO_ID, FERDIUM_ID]
                                 if identifier in args[2]}
            return ''
        if program == sys.executable:
            return self.collect(list(args))
        raise AssertionError(f'Unexpected command {args}')

    def argv_for(self, program):
        return [call for call in self.calls if call[0] == program]


class BenchmarkSessionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.output = root / 'benchmarks'
        self.output.mkdir()
        self.app = root / 'Paguro.app'
        self.app.mkdir()
        self.settings = root / 'settings.json'
        self.settings.write_text('[]')

    def argv(self, *extra):
        return ['--scenario', 'awake', '--pairs', '1', '--services', 'One, Two',
                '--paguro-app', str(self.app), '--release-build-settings', str(self.settings),
                '--output', str(self.output), '--samples', '3', '--interval', '1',
                *extra]

    def drive(self, fake, *extra):
        """Run one session with every external effect patched out."""
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.ExitStack() as stack:
            stack.enter_context(mock.patch.object(benchmark_session, 'command', fake))
            popen = stack.enter_context(mock.patch.object(benchmark_session.subprocess, 'Popen'))
            stack.enter_context(mock.patch.object(benchmark_session.time, 'sleep'))
            stack.enter_context(mock.patch.object(
                os, 'kill', side_effect=AssertionError('the session must never signal a process')))
            stack.enter_context(mock.patch.object(sys, 'argv', ['benchmark_session.py', *self.argv(*extra)]))
            stack.enter_context(contextlib.redirect_stdout(stdout))
            stack.enter_context(contextlib.redirect_stderr(stderr))
            with self.assertRaises(SystemExit) as exit:
                benchmark_session.main()
        manifests = sorted(self.output.glob('session-*.json'))
        manifest = json.loads(manifests[-1].read_text()) if manifests else None
        return exit.exception.code, manifest, stdout.getvalue() + stderr.getvalue(), popen

    def test_battery_is_refused_unless_allowed(self):
        code, manifest, output, popen = self.drive(FakeCommand(self.app, battery=True))
        self.assertEqual((code, manifest), (1, None))
        self.assertIn('battery power', output)
        popen.assert_not_called()
        code, manifest, _, _ = self.drive(FakeCommand(self.app, battery=True), '--allow-battery')
        self.assertEqual(code, 0)
        self.assertEqual(manifest['status'], 'complete')
        self.assertIn('Battery Power', manifest['environment']['power_start'])

    def test_host_swap_above_the_limit_refuses_before_anything_runs(self):
        fake = FakeCommand(self.app, swap_mib=10647.06)
        code, manifest, output, popen = self.drive(fake)
        self.assertEqual((code, manifest), (1, None))
        self.assertIn('10647 MiB of swap in use', output)
        self.assertIn('1024 MiB limit', output)
        self.assertIn('footprint excludes swapped pages', output)
        popen.assert_not_called()
        for program in ['/usr/bin/open', '/usr/bin/osascript', sys.executable]:
            self.assertEqual(fake.argv_for(program), [])
        self.assertEqual(list(self.output.iterdir()), [])

    def test_allow_swap_measures_a_pressured_host_and_still_records_it(self):
        fake = FakeCommand(self.app, swap_mib=10647.06)
        code, manifest, _, _ = self.drive(fake, '--allow-swap')
        self.assertEqual((code, manifest['status']), (0, 'complete'))
        self.assertAlmostEqual(manifest['environment']['swap_used_mib_start'], 10647.06)

    def test_max_swap_mib_raises_the_limit(self):
        code, manifest, output, _ = self.drive(FakeCommand(self.app, swap_mib=2048.0))
        self.assertEqual((code, manifest), (1, None))
        self.assertIn('2048 MiB of swap in use', output)
        code, manifest, _, _ = self.drive(FakeCommand(self.app, swap_mib=2048.0),
                                          '--max-swap-mib', '4096')
        self.assertEqual((code, manifest['status']), (0, 'complete'))

    def test_unreadable_swap_usage_stops_the_session(self):
        fake = FakeCommand(self.app, swap_output='vm.swapusage: (encrypted)\n')
        code, manifest, output, popen = self.drive(fake)
        self.assertEqual((code, manifest), (1, None))
        self.assertIn('Could not read swap usage', output)
        popen.assert_not_called()
        self.assertEqual(fake.argv_for('/usr/bin/open'), [])

    def test_swap_is_recorded_at_both_ends_of_a_session(self):
        fake = FakeCommand(self.app)
        code, manifest, _, _ = self.drive(fake)
        self.assertEqual((code, manifest['status']), (0, 'complete'))
        self.assertEqual(manifest['environment']['swap_used_mib_start'], 120.0)
        self.assertEqual(manifest['environment']['swap_used_mib_end'], 120.0)
        self.assertEqual([call for call in fake.argv_for('/usr/sbin/sysctl')
                          if call[1] == 'vm.swapusage'],
                         [['/usr/sbin/sysctl', 'vm.swapusage']] * 2)

    def test_a_dry_run_still_reads_and_reports_swap(self):
        code, manifest, output, _ = self.drive(FakeCommand(self.app), '--dry-run')
        self.assertEqual((code, manifest), (0, None))
        self.assertIn('Host swap in use: 120 MiB', output)
        code, manifest, output, _ = self.drive(FakeCommand(self.app, swap_mib=5000.0), '--dry-run')
        self.assertEqual((code, manifest), (1, None))
        self.assertIn('5000 MiB of swap in use', output)

    def test_a_running_xcode_stops_the_session(self):
        code, manifest, output, popen = self.drive(FakeCommand(self.app, xcode=True))
        self.assertEqual((code, manifest), (1, None))
        self.assertIn('Xcode is running', output)
        self.assertEqual(popen.call_count, 0)

    def test_either_app_already_running_stops_the_session(self):
        for bundle_id in [PAGURO_ID, FERDIUM_ID]:
            with self.subTest(bundle_id=bundle_id):
                fake = FakeCommand(self.app, running=[bundle_id])
                code, manifest, output, _ = self.drive(fake)
                self.assertEqual((code, manifest), (1, None))
                self.assertIn('already running', output)
                self.assertEqual(fake.argv_for('/usr/bin/osascript'), [])
                self.assertEqual(fake.argv_for('/usr/bin/open'), [])

    def test_a_different_paguro_bundle_path_stops_the_first_run(self):
        other = Path(self.directory.name) / 'DerivedData/Debug/Paguro.app'
        fake = FakeCommand(self.app, paguro_path=other)
        code, manifest, _, _ = self.drive(fake)
        self.assertEqual(code, 1)
        self.assertEqual(manifest['status'], 'aborted')
        self.assertIn(str(other), manifest['error'])
        self.assertIn(str(self.app.resolve()), manifest['error'])
        self.assertEqual(manifest['runs'][0]['status'], 'incomplete')
        self.assertEqual(fake.argv_for(sys.executable), [])

    def test_app_order_alternates_every_pair(self):
        fake = FakeCommand(self.app)
        code, manifest, _, _ = self.drive(fake, '--pairs', '3')
        self.assertEqual((code, manifest['status']), (0, 'complete'))
        self.assertEqual([run['app'] for run in manifest['runs']],
                         ['Paguro', 'Ferdium', 'Ferdium', 'Paguro', 'Paguro', 'Ferdium'])
        self.assertEqual([call[1:] for call in fake.argv_for('/usr/bin/open')],
                         [['-n', str(self.app)], ['-b', FERDIUM_ID],
                          ['-b', FERDIUM_ID], ['-n', str(self.app)],
                          ['-n', str(self.app)], ['-b', FERDIUM_ID]])
        self.assertEqual([run['label'] for run in manifest['runs'][:2]],
                         ['Paguro awake run 1', 'Ferdium awake run 1'])

    def test_first_ferdium_reverses_the_opening_pair(self):
        fake = FakeCommand(self.app)
        code, manifest, _, _ = self.drive(fake, '--pairs', '2', '--first', 'ferdium')
        self.assertEqual(code, 0)
        self.assertEqual([run['app'] for run in manifest['runs']],
                         ['Ferdium', 'Paguro', 'Paguro', 'Ferdium'])

    def test_a_failing_collector_records_its_stderr(self):
        fake = FakeCommand(self.app, collector_error='Measurement stopped: footprint reported an error\n')
        code, manifest, _, _ = self.drive(fake)
        self.assertEqual((code, manifest['status']), (1, 'aborted'))
        self.assertIn('footprint reported an error', manifest['error'])
        self.assertIn('footprint reported an error', manifest['runs'][0]['error'])
        self.assertEqual(manifest['runs'][0]['status'], 'incomplete')
        self.assertIsNone(manifest['runs'][0]['run_dir'])

    def test_a_collector_without_a_saved_line_stops_the_session(self):
        fake = FakeCommand(self.app, collector_stdout='Recording to /tmp/somewhere\n')
        code, manifest, _, _ = self.drive(fake)
        self.assertEqual((code, manifest['status']), (1, 'aborted'))
        self.assertIn('Saved', manifest['error'])
        self.assertIsNone(manifest['runs'][0]['run_dir'])
        self.assertEqual(manifest['runs'][1]['status'], 'not-started')

    def test_an_app_that_will_not_quit_is_never_killed(self):
        fake = FakeCommand(self.app, quits=False)
        code, manifest, _, _ = self.drive(fake)
        self.assertEqual((code, manifest['status']), (1, 'aborted'))
        self.assertIn('not killing it', manifest['error'])
        self.assertEqual(len(fake.argv_for('/usr/bin/osascript')), 1)
        self.assertEqual(fake.argv_for('/bin/kill'), [])
        self.assertEqual(manifest['runs'][0]['status'], 'incomplete')
        self.assertEqual(manifest['runs'][0]['run_dir'], str(fake.run_dirs[0]))

    def test_too_few_processes_stops_the_run_before_collecting(self):
        fake = FakeCommand(self.app)
        code, manifest, _, _ = self.drive(fake, '--min-processes', '4')
        self.assertEqual((code, manifest['status']), (1, 'aborted'))
        self.assertIn('a service may not have loaded', manifest['error'])
        self.assertEqual(fake.argv_for(sys.executable), [])

    def test_the_manifest_is_prepopulated_and_rewritten_around_an_abort(self):
        fake = FakeCommand(self.app, collector_error='boom\n')
        code, manifest, _, popen = self.drive(fake, '--pairs', '2', '--notes', 'idle')
        self.assertEqual(code, 1)
        self.assertEqual(len(manifest['runs']), 4)
        self.assertEqual([run['status'] for run in manifest['runs']],
                         ['incomplete', 'not-started', 'not-started', 'not-started'])
        self.assertEqual(manifest['schema'], 1)
        self.assertEqual(manifest['pairs_requested'], 2)
        self.assertEqual(manifest['services'], 'One, Two')
        self.assertEqual(manifest['paguro'],
                         {'app_path': str(self.app.resolve()), 'bundle_id': PAGURO_ID,
                          'release_build_settings': str(self.settings.resolve())})
        self.assertEqual(manifest['ferdium'], {'bundle_id': FERDIUM_ID})
        self.assertEqual(manifest['environment']['macos'], '15.5')
        self.assertIn('AC Power', manifest['environment']['power_end'])
        self.assertIsNotNone(manifest['finished_at'])
        popen.return_value.terminate.assert_called_once()

    def test_a_complete_session_copies_the_collector_status(self):
        fake = FakeCommand(self.app)
        code, manifest, output, popen = self.drive(fake, '--notes', 'idle')
        self.assertEqual((code, manifest['status'], manifest['error']), (0, 'complete', None))
        self.assertEqual([run['status'] for run in manifest['runs']],
                         ['complete-unreviewed', 'complete-unreviewed'])
        self.assertEqual([run['run_dir'] for run in manifest['runs']],
                         [str(path) for path in fake.run_dirs])
        collector = fake.argv_for(sys.executable)
        self.assertEqual(collector[0][2:], ['--bundle-id', PAGURO_ID, '--label', 'Paguro awake run 1',
                                            '--scenario', 'awake', '--services', 'One, Two',
                                            '--notes', 'idle', '--samples', '3', '--interval', '1.0',
                                            '--output', str(self.output),
                                            '--release-build-settings', str(self.settings)])
        self.assertNotIn('--release-build-settings', collector[1])
        self.assertEqual(popen.call_args[0][0][:2], ['/usr/bin/caffeinate', '-dimsu'])
        self.assertIn('Session complete', output)

    def test_a_dry_run_changes_nothing(self):
        fake = FakeCommand(self.app)
        code, manifest, output, popen = self.drive(fake, '--pairs', '2', '--dry-run')
        self.assertEqual((code, manifest), (0, None))
        popen.assert_not_called()
        for program in ['/usr/bin/open', '/usr/bin/osascript', sys.executable]:
            self.assertEqual(fake.argv_for(program), [])
        self.assertEqual(list(self.output.iterdir()), [])
        self.assertIn('session-', output)
        self.assertIn(f'"-b", "{FERDIUM_ID}"', output)
        self.assertIn('benchmark_memory.py', output)
        self.assertEqual([line.split(': ')[-1] for line in output.splitlines()
                          if line.startswith('--- pair')],
                         ['Paguro awake run 1', 'Ferdium awake run 1',
                          'Ferdium awake run 2', 'Paguro awake run 2'])


if __name__ == '__main__':
    unittest.main()
