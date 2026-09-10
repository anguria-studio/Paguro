#!/usr/bin/env python3
"""Drive matched Paguro and Ferdium memory runs for one benchmark scenario."""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from benchmark_memory import app_group

ROOT = Path(__file__).resolve().parent.parent
COLLECTOR = ROOT / 'scripts/benchmark_memory.py'
LISTING = ('/usr/bin/lsappinfo', 'list')
XCODE_BUNDLE_ID = 'com.apple.dt.Xcode'
POLL_SECONDS = 2
LAUNCH_TIMEOUT = 60
QUIT_TIMEOUT = 45
MEMBERSHIP_GAP_SECONDS = 20
COOLDOWN_SECONDS = 15
COLLECTOR_GRACE_SECONDS = 600
SAVED = re.compile(r'(?m)^Saved (.+)/report\.json$')
SWAP_USED = re.compile(r'used\s*=\s*([0-9.]+)M')


class Abort(Exception):
    """Stop the session; the reason is recorded in the manifest."""


def command(*args, timeout=30):
    return subprocess.run(args, check=True, capture_output=True, text=True,
                          timeout=timeout).stdout


def swap_used_mib():
    """Host-wide swap in use; footprint excludes swapped-out pages, so it matters."""
    output = command('/usr/sbin/sysctl', 'vm.swapusage')
    match = SWAP_USED.search(output)
    if not match:
        raise Abort('Could not read swap usage from /usr/sbin/sysctl vm.swapusage; '
                    f'it printed {output.strip()!r} with no "used = <number>M" figure.')
    return float(match[1])


def log(message):
    print(f'[{datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] {message}', flush=True)


def polls(seconds):
    """Count attempts instead of wall clock, so a stopped clock cannot spin."""
    return range(max(1, int(seconds // POLL_SECONDS)))


class Session:
    def __init__(self, args):
        self.args = args
        self.manifest = None
        self.manifest_path = None
        self.caffeinate = None

    # Reads -------------------------------------------------------------

    def listing(self):
        return command(*LISTING)

    def is_running(self, bundle_id, listing=None):
        listing = self.listing() if listing is None else listing
        return f'bundleID="{bundle_id}"' in listing

    def power(self):
        lines = command('/usr/bin/pmset', '-g', 'batt').splitlines()
        return lines[0] if lines else '', '\n'.join(line.strip() for line in lines[:2])

    # Manifest ----------------------------------------------------------

    def plan(self):
        first = self.args.first.capitalize()
        other = 'Ferdium' if first == 'Paguro' else 'Paguro'
        runs = []
        for pair in range(1, self.args.pairs + 1):
            leader = first if pair % 2 else other
            for order, app in enumerate([leader, 'Ferdium' if leader == 'Paguro' else 'Paguro'], 1):
                runs.append({'pair': pair, 'order': order, 'app': app,
                             'bundle_id': self.bundle_id(app),
                             'label': f'{app} {self.args.scenario} run {pair}',
                             'run_dir': None, 'status': 'not-started', 'error': None})
        return runs

    def bundle_id(self, app):
        return self.args.paguro_bundle_id if app == 'Paguro' else self.args.ferdium_bundle_id

    def build_manifest(self, power_start, swap_start):
        stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        self.manifest_path = self.args.output / f'session-{stamp}-{self.args.scenario}.json'
        self.manifest = {
            'schema': 1, 'scenario': self.args.scenario, 'pairs_requested': self.args.pairs,
            'services': self.args.services, 'first': self.args.first,
            'started_at': datetime.now(timezone.utc).isoformat(),
            'finished_at': None, 'status': 'running', 'error': None,
            'environment': {'macos': command('/usr/bin/sw_vers', '-productVersion').strip(),
                            'model': command('/usr/sbin/sysctl', '-n', 'hw.model').strip(),
                            'power_start': power_start, 'power_end': None,
                            'swap_used_mib_start': swap_start, 'swap_used_mib_end': None},
            'paguro': {'app_path': str(self.args.paguro_app.resolve()),
                       'bundle_id': self.args.paguro_bundle_id,
                       'release_build_settings': str(self.args.release_build_settings.resolve())},
            'ferdium': {'bundle_id': self.args.ferdium_bundle_id},
            'runs': self.plan(),
        }

    def write(self):
        if self.manifest is None or self.args.dry_run:
            return
        self.manifest_path.write_text(json.dumps(self.manifest, indent=2) + '\n')

    def fail(self, entry, reason):
        entry['status'] = 'incomplete'
        entry['error'] = reason
        raise Abort(reason)

    # Commands ----------------------------------------------------------

    def launch_argv(self, app):
        if app == 'Paguro':
            return ['/usr/bin/open', '-n', str(self.args.paguro_app)]
        return ['/usr/bin/open', '-b', self.args.ferdium_bundle_id]

    def quit_argv(self, bundle_id):
        return ['/usr/bin/osascript', '-e',
                f'tell application id "{bundle_id}" to quit']

    def collector_argv(self, entry):
        argv = [sys.executable, str(COLLECTOR),
                '--bundle-id', entry['bundle_id'], '--label', entry['label'],
                '--scenario', self.args.scenario, '--services', self.args.services,
                '--notes', self.args.notes, '--samples', str(self.args.samples),
                '--interval', str(self.args.interval), '--output', str(self.args.output)]
        if entry['app'] == 'Paguro':
            argv += ['--release-build-settings', str(self.args.release_build_settings)]
        return argv

    # Session -----------------------------------------------------------

    def preflight(self):
        first_line, power_start = self.power()
        if 'Battery Power' in first_line and not self.args.allow_battery:
            raise Abort('The Mac is on battery power, which changes memory and power '
                        'behavior; connect power or pass --allow-battery.')
        swap_start = swap_used_mib()
        if swap_start > self.args.max_swap_mib and not self.args.allow_swap:
            raise Abort(f'The host has {swap_start:.0f} MiB of swap in use, above the '
                        f'{self.args.max_swap_mib:.0f} MiB limit: quit unrelated apps and let the '
                        'Mac settle, or pass --allow-swap. footprint excludes swapped pages, so a '
                        'pressured host under-reports memory.')
        log(f'Host swap in use: {swap_start:.0f} MiB')
        return power_start, swap_start

    def checks(self):
        listing = self.listing()
        if f'bundleID="{XCODE_BUNDLE_ID}"' in listing:
            raise Abort('Xcode is running; quit it so no debugger or build affects the runs.')
        for app in ['Paguro', 'Ferdium']:
            if self.is_running(self.bundle_id(app), listing):
                raise Abort(f'{app} ({self.bundle_id(app)}) is already running; quit it '
                            'yourself and start a new session. This session will not quit it '
                            'for you, and a stale Xcode Debug build must not be measured.')
        if not self.args.paguro_app.exists() or self.args.paguro_app.suffix != '.app':
            raise Abort(f'--paguro-app must be an existing .app bundle: {self.args.paguro_app}')
        if not self.args.release_build_settings.exists():
            raise Abort(f'--release-build-settings does not exist: {self.args.release_build_settings}')

    def measure(self, entry):
        app, bundle_id = entry['app'], entry['bundle_id']
        log(f'Pair {entry["pair"]} run {entry["order"]}: {app}')
        if self.is_running(bundle_id):
            self.fail(entry, f'{app} is already running before its run; quit it manually '
                             'and start a new session.')

        log(f'Launching {app}')
        command(*self.launch_argv(app))

        group = None
        for attempt in polls(LAUNCH_TIMEOUT):
            try:
                group = app_group(self.listing(), bundle_id)
                break
            except ValueError as error:
                if attempt == polls(LAUNCH_TIMEOUT)[-1]:
                    self.fail(entry, f'{app} did not present exactly one running instance '
                                     f'within {LAUNCH_TIMEOUT} s: {error}')
                time.sleep(POLL_SECONDS)
        if app == 'Paguro':
            launched = Path(group['bundle_path']).resolve()
            expected = self.args.paguro_app.resolve()
            if launched != expected:
                self.fail(entry, f'The running Paguro is {launched}, not the requested '
                                 f'{expected}; quit it and launch the Release build only.')
        log(f'{app} is running as pids {group["pids"]}')

        log(f'Settling for {self.args.settle_seconds} s')
        time.sleep(self.args.settle_seconds)
        before = app_group(self.listing(), bundle_id)['pids']
        time.sleep(MEMBERSHIP_GAP_SECONDS)
        after = app_group(self.listing(), bundle_id)['pids']
        if before != after:
            self.fail(entry, f'{app} membership not stable: {before} then {after}; '
                             'let it settle and start a new session.')
        if self.args.min_processes and len(after) < self.args.min_processes:
            self.fail(entry, f'{app} has {len(after)} processes, fewer than the required '
                             f'{self.args.min_processes} — too few processes, a service '
                             'may not have loaded.')

        log(f'Collecting {entry["label"]}')
        timeout = self.args.samples * self.args.interval + COLLECTOR_GRACE_SECONDS
        try:
            stdout = command(*self.collector_argv(entry), timeout=timeout)
        except subprocess.CalledProcessError as error:
            self.fail(entry, f'The collector exited {error.returncode} for {entry["label"]}: '
                             f'{(error.stderr or "").strip()}')
        except subprocess.SubprocessError as error:
            self.fail(entry, f'The collector did not finish for {entry["label"]}: {error}')
        saved = SAVED.search(stdout)
        if not saved:
            self.fail(entry, 'The collector printed no "Saved .../report.json" line; '
                             'no run directory can be recorded.')
        entry['run_dir'] = saved[1]
        report = json.loads((Path(saved[1]) / 'report.json').read_text())
        entry['status'] = report.get('status', 'unknown')
        log(f'Saved {entry["run_dir"]} ({entry["status"]})')
        self.write()

        log(f'Quitting {app}')
        command(*self.quit_argv(bundle_id))
        for attempt in polls(QUIT_TIMEOUT):
            if not self.is_running(bundle_id):
                break
            if attempt == polls(QUIT_TIMEOUT)[-1]:
                self.fail(entry, f'{app} did not quit within {QUIT_TIMEOUT} s; not killing '
                                 'it — quit it manually and start a new session.')
            time.sleep(POLL_SECONDS)

        log(f'Cooling down for {COOLDOWN_SECONDS} s')
        time.sleep(COOLDOWN_SECONDS)

    def dry_run(self):
        print(f'Manifest would be written to {self.manifest_path}', flush=True)
        print('Would spawn: ' + ' '.join(['/usr/bin/caffeinate', '-dimsu', '-w', '<pid>']),
              flush=True)
        for entry in self.manifest['runs']:
            print(f'--- pair {entry["pair"]} run {entry["order"]}: {entry["label"]}', flush=True)
            steps = [('not already running', list(LISTING)),
                     ('launch', self.launch_argv(entry['app'])),
                     (f'identity, every {POLL_SECONDS} s for up to {LAUNCH_TIMEOUT} s', list(LISTING)),
                     (f'membership after {self.args.settle_seconds} s settling', list(LISTING)),
                     (f'membership again {MEMBERSHIP_GAP_SECONDS} s later', list(LISTING)),
                     ('collect', self.collector_argv(entry)),
                     ('quit', self.quit_argv(entry['bundle_id'])),
                     (f'gone, every {POLL_SECONDS} s for up to {QUIT_TIMEOUT} s', list(LISTING))]
            for note, argv in steps:
                print(f'  {json.dumps(argv)}  # {note}', flush=True)
        print('Dry run only; nothing was launched, quit, or written.', flush=True)

    def run(self):
        try:
            power_start, swap_start = self.preflight()
            self.checks()
            self.build_manifest(power_start, swap_start)
            if self.args.dry_run:
                self.dry_run()
                return 0
            self.args.output.mkdir(parents=True, exist_ok=True)
            self.write()
            log(f'Session manifest {self.manifest_path}')
            self.caffeinate = subprocess.Popen(
                ['/usr/bin/caffeinate', '-dimsu', '-w', str(os.getpid())])
            for entry in self.manifest['runs']:
                try:
                    self.measure(entry)
                except Abort:
                    raise
                except (subprocess.SubprocessError, OSError, ValueError) as error:
                    self.fail(entry, f'{entry["label"]} stopped: {error}')
            self.manifest['status'] = 'complete'
            log('Session complete')
            return 0
        except (Abort, subprocess.SubprocessError, OSError, ValueError, KeyboardInterrupt) as error:
            reason = str(error) or 'Interrupted'
            if self.manifest is not None:
                self.manifest['status'] = 'aborted'
                self.manifest['error'] = reason
            print(f'Session aborted: {reason}', file=sys.stderr, flush=True)
            return 1
        finally:
            if self.caffeinate is not None:
                self.caffeinate.terminate()
            if self.manifest is not None:
                self.manifest['finished_at'] = datetime.now(timezone.utc).isoformat()
                try:
                    self.manifest['environment']['power_end'] = self.power()[1]
                except (subprocess.SubprocessError, OSError):
                    pass
                try:
                    self.manifest['environment']['swap_used_mib_end'] = swap_used_mib()
                except (Abort, subprocess.SubprocessError, OSError):
                    pass
                self.write()


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenario', choices=['awake', 'hibernated'], required=True,
                        help='Workload state to measure; passed to every collector run')
    parser.add_argument('--pairs', type=int, default=5,
                        help='Matched Paguro/Ferdium pairs to run (default 5, minimum 1)')
    parser.add_argument('--services', required=True,
                        help='Service names only, verbatim to every run; no account identifiers')
    parser.add_argument('--paguro-app', type=Path, required=True,
                        help='Release .app bundle to launch for the Paguro runs')
    parser.add_argument('--paguro-bundle-id', default='studio.anguria.paguro.debug',
                        help='Bundle id of the Paguro build being measured')
    parser.add_argument('--ferdium-bundle-id', default='org.ferdium.ferdium-app',
                        help='Bundle id of the comparison app')
    parser.add_argument('--release-build-settings', type=Path, required=True,
                        help='xcodebuild -showBuildSettings -json, passed to Paguro runs only')
    parser.add_argument('--settle-seconds', type=float, default=120,
                        help='Idle time after launch before the membership probes (default 120)')
    parser.add_argument('--min-processes', type=int, default=0,
                        help='Require at least this many processes after settling (0 disables)')
    parser.add_argument('--samples', type=int, default=31,
                        help='Samples per run, passed through to the collector (default 31)')
    parser.add_argument('--interval', type=float, default=10,
                        help='Seconds between samples, passed through (default 10)')
    parser.add_argument('--output', type=Path, default=ROOT / '.project/benchmarks',
                        help='Directory for run folders and the session manifest')
    parser.add_argument('--notes', default='',
                        help='Run notes, passed through to the collector')
    parser.add_argument('--first', choices=['paguro', 'ferdium'], default='paguro',
                        help='App measured first in pair 1; the order alternates each pair')
    parser.add_argument('--allow-battery', action='store_true',
                        help='Measure on battery power; refused by default')
    parser.add_argument('--max-swap-mib', type=float, default=1024,
                        help='Refuse to start above this much host swap in use (default 1024); '
                             'footprint excludes swapped-out pages')
    parser.add_argument('--allow-swap', action='store_true',
                        help='Measure with host swap above --max-swap-mib; refused by default '
                             'because a pressured host under-reports memory')
    parser.add_argument('--dry-run', action='store_true',
                        help='Run the read-only checks, print every planned command, change nothing')
    args = parser.parse_args(argv)
    if args.pairs < 1:
        parser.error('--pairs must be at least 1')
    if args.samples < 2:
        parser.error('--samples must be at least 2')
    if args.interval <= 0 or args.settle_seconds < 0 or args.min_processes < 0:
        parser.error('--interval must be positive; --settle-seconds and --min-processes cannot be negative')
    return args


def main():
    raise SystemExit(Session(parse_args()).run())


if __name__ == '__main__':
    main()
