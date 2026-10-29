#!/usr/bin/env python3
"""Measure the memory cost of browser extensions across several services.

The script runs the opt-in ExtensionMemoryMeasurementTests test. At each
marker the test prints, it measures the test host's whole process group with
`footprint`, the same way scripts/benchmark_memory.py does. It downloads
public Firefox packages and opens only throwaway accounts.

Example:
    scripts/measure_extension_memory.py --output .project/extension-memory
"""

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))
from benchmark_memory import discover, sample  # noqa: E402

TEST = 'PaguroTests/ExtensionMemoryMeasurementTests/testMemoryPhasesWhenExplicitlyRequested'
MARKER = re.compile(r'EXTENSION-MEMORY (idle|ready) phase=(\S+) services=(\d+)')
PACKAGE = re.compile(r'EXTENSION-MEMORY package slug=(\S+) version=(\S+) sha256=([0-9a-f]{64})')
MIB = 1024 * 1024
WEB_CONTENT = 'com.apple.WebKit.WebContent'
PREWARMED_LIMIT = 16 * MIB


def parse_marker(line):
    """Return (kind, phase, services) for a measurement marker, or None."""
    match = MARKER.search(line)
    return (match[1], match[2], int(match[3])) if match else None


def processes_in(payload):
    """Map each pid in a footprint sample to its name and footprint in bytes."""
    return {str(process['pid']): {'name': process.get('name', '?'), 'bytes': process['footprint']}
            for process in payload['processes']}


def measure(bundle_id, path, attempts=3):
    """Processes can exit between discovery and sampling, so retry a few times."""
    for attempt in range(attempts):
        try:
            group = discover(bundle_id)
            total = sample(group, path)
            return {'footprint_bytes': total, 'processes': processes_in(json.loads(path.read_text()))}
        except (ValueError, subprocess.CalledProcessError):
            if attempt == attempts - 1:
                raise
    raise AssertionError('unreachable')


def new_process_bytes(idle, ready):
    """Footprint of the processes that a phase started.

    The Debug test host also runs the services saved in its own store. Their
    processes grow and shrink on their own, so a group total cannot show the
    cost of a phase. Processes that exist before the phase are left out.
    """
    total, started = 0, 0
    for pid, values in ready['processes'].items():
        before = idle['processes'].get(pid)
        if before is None:
            total, started = total + values['bytes'], started + 1
        elif before['name'] == WEB_CONTENT and before['bytes'] < PREWARMED_LIMIT:
            # WebKit keeps a small prewarmed process ready, and the next new view takes it.
            total, started = total + max(0, values['bytes'] - before['bytes']), started + 1
    return total, started


def summarize(samples):
    """Cost of each phase's new processes, and each extension's cost above baseline."""
    rows = {}
    for entry in samples:
        rows.setdefault((entry['phase'], entry['services']), {})[entry['kind']] = entry
    phases = {key: new_process_bytes(values['idle'], values['ready']) for key, values in rows.items()
              if 'ready' in values and 'idle' in values}
    table = []
    for (phase, services), (cost, started) in sorted(phases.items(), key=lambda item: (item[0][1], item[0][0])):
        baseline = phases.get(('baseline', services), (None, 0))[0]
        extra = None if phase == 'baseline' or baseline is None else cost - baseline
        table.append({'phase': phase, 'services': services, 'phase_bytes': cost, 'new_processes': started,
                      'extension_bytes': extra,
                      'extension_bytes_per_service': None if extra is None else extra / services})
    return table


def format_table(table):
    lines = ['| Phase | Services | New processes | Their footprint (MiB) | Extension cost (MiB) | Per service (MiB) |',
             '| --- | --- | --- | --- | --- | --- |']
    for row in table:
        extra = '' if row['extension_bytes'] is None else f"{row['extension_bytes'] / MIB:.0f}"
        each = '' if row['extension_bytes_per_service'] is None else f"{row['extension_bytes_per_service'] / MIB:.0f}"
        lines.append(f"| {row['phase']} | {row['services']} | {row['new_processes']} | "
                     f"{row['phase_bytes'] / MIB:.0f} | {extra} | {each} |")
    return '\n'.join(lines)


def run(args):
    output = args.output.resolve() / datetime.now().strftime('%Y%m%d-%H%M%S')
    output.mkdir(parents=True, exist_ok=False)
    common = ['xcodebuild', '-project', str(ROOT / 'Paguro.xcodeproj'), '-scheme', 'Paguro',
              '-configuration', 'Debug', '-derivedDataPath', str(args.derived_data.resolve())]
    if not args.skip_build:
        subprocess.run(common + ['build-for-testing'], check=True, stdout=subprocess.DEVNULL)
    # xcodebuild forwards TEST_RUNNER_ variables from its own environment to the test.
    environment = dict(os.environ,
                       TEST_RUNNER_PAGURO_EXTENSION_MEMORY='1',
                       TEST_RUNNER_PAGURO_EXTENSION_MEMORY_COUNTS=args.counts,
                       TEST_RUNNER_PAGURO_EXTENSION_MEMORY_SLUGS=args.slugs)
    command = common + ['test-without-building', f'-only-testing:{TEST}', '-test-timeouts-enabled', 'NO']
    samples, packages = [], []
    with (output / 'xcodebuild.log').open('w') as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                   env=environment)
        for line in process.stdout:
            log.write(line)
            if package := PACKAGE.search(line):
                packages.append({'slug': package[1], 'version': package[2], 'sha256': package[3]})
            marker = parse_marker(line)
            if not marker:
                continue
            kind, phase, services = marker
            values = []
            for index in range(args.samples):
                path = output / f'{phase}-{services}-{kind}-{index + 1}.json'
                values.append(measure(args.bundle_id, path))
            # A phase's processes are compared by pid, so keep one consistent snapshot.
            entry = {'kind': kind, 'phase': phase, 'services': services,
                     'footprint_bytes': statistics.median(v['footprint_bytes'] for v in values),
                     'processes': values[-1]['processes']}
            samples.append(entry)
            print(f"{kind:5} {phase:28} services={services:2} "
                  f"group={entry['footprint_bytes'] / MIB:6.0f} MiB  processes={len(entry['processes'])}", flush=True)
        if process.wait() != 0:
            raise SystemExit(f'xcodebuild failed; see {output / "xcodebuild.log"}')
    if not samples:
        raise SystemExit(f'The test recorded no phases. It may have skipped; see {output / "xcodebuild.log"}')
    table = summarize(samples)
    result = {'schema': 1, 'finished_at': datetime.now(timezone.utc).isoformat(),
              'note': 'Debug test host. Phase cost counts only processes started during the phase.',
              'packages': packages, 'samples': samples, 'table': table}
    (output / 'result.json').write_text(json.dumps(result, indent=2))
    print()
    print(format_table(table))
    print(f'\nSaved to {output}')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--output', type=Path, default=ROOT / '.project/extension-memory')
    parser.add_argument('--derived-data', type=Path, default=ROOT / '.project/extension-memory/DerivedData')
    parser.add_argument('--bundle-id', default='studio.anguria.paguro.debug')
    parser.add_argument('--counts', default='1,5,10')
    parser.add_argument('--slugs', default='darkreader,bitwarden-password-manager,simple-translate')
    parser.add_argument('--samples', type=int, default=2)
    parser.add_argument('--skip-build', action='store_true')
    run(parser.parse_args())


if __name__ == '__main__':
    main()
