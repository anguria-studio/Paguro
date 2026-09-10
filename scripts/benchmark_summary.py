#!/usr/bin/env python3
"""Summarize matched benchmark runs into one reviewable comparison."""

import argparse
import json
import math
import re
import statistics
import sys
from pathlib import Path

MIB = 1048576
FERDIUM_BUNDLE_ID = 'org.ferdium.ferdium-app'
PAGURO_BUNDLE_PREFIX = 'studio.anguria.paguro'
APPS = ['Paguro', 'Ferdium']
COMPLETE = 'complete-unreviewed'
REPEATABLE = 'repeatable'
INCONCLUSIVE = 'mixed or inconclusive'
UNREVIEWED = ' — unreviewed; do not publish'
NO_CLAIM = 'No comparative claim is supported by this session.'
SWAP_LIMIT_MIB = 1024


class Refusal(Exception):
    """Every reason a session cannot be summarized, reported together."""

    def __init__(self, reasons):
        super().__init__('\n'.join(reasons))
        self.reasons = reasons


def mib(value):
    return round(value / MIB, 1)


def app_for(bundle_id):
    if bundle_id == FERDIUM_BUNDLE_ID:
        return 'Ferdium'
    if str(bundle_id).startswith(PAGURO_BUNDLE_PREFIX):
        return 'Paguro'
    raise ValueError(f'Unknown bundle identifier {bundle_id!r}; cannot tell which app produced this run.')


def power_source(text):
    """pmset names the source on its first line; a charged Mac still lists a battery."""
    match = re.search(r"Now drawing from '([^']+)'", text or '')
    source = match[1] if match else str(text or '')
    if 'Battery' in source:
        return 'Battery'
    if 'AC' in source:
        return 'AC Power'
    return 'unrecorded power source'


def swap_mib(value):
    return f'{value:.0f}' if isinstance(value, (int, float)) else 'unrecorded'


def host_swap(manifest):
    """Swap at both ends of the session; older manifests recorded neither."""
    environment = (manifest or {}).get('environment') or {}
    return {'start': environment.get('swap_used_mib_start'),
            'end': environment.get('swap_used_mib_end')}


def swap_warnings(swap):
    """A warning, never a refusal: footprint excludes pages the host swapped out."""
    values = [value for value in [swap['start'], swap['end']] if isinstance(value, (int, float))]
    if not any(value > SWAP_LIMIT_MIB for value in values):
        return []
    return [f"Host swap was {swap_mib(swap['start'])} MiB at session start and "
            f"{swap_mib(swap['end'])} MiB at the end; footprint excludes swapped pages, so runs "
            'under host memory pressure can under-report. Treat this session as reference only '
            'unless swap was low.']


def read_run(run_dir):
    directory = Path(run_dir).expanduser()
    report = directory if directory.name == 'report.json' else directory / 'report.json'
    if not report.is_file():
        raise ValueError(f'No report.json in {directory}; a run without a report cannot be summarized.')
    payload = json.loads(report.read_text())
    return {'app': app_for(payload.get('bundle_id')), 'label': payload.get('label') or report.parent.name,
            'run_dir': str(report.parent.resolve()), 'report': payload}


NEVER_STARTED = 'never started (no run directory)'


def unstarted_run(entry):
    """A manifest entry the session never reached: a placeholder, never read from disk."""
    error = entry.get('error')
    return {'app': entry.get('app') or app_for(entry.get('bundle_id')),
            'label': entry.get('label') or f"pair {entry.get('pair')} run {entry.get('order')}",
            'run_dir': None, 'status': entry.get('status', 'not-started'),
            'reason': NEVER_STARTED + (f': {error}' if error else '')}


def unstarted_error(run):
    return run['reason'][len(NEVER_STARTED) + 2:] or 'no error recorded'


def load_manifest(path):
    """A manifest pre-lists every planned run, so an aborted session carries entries with no run_dir."""
    manifest = json.loads(Path(path).expanduser().read_text())
    entries = manifest.get('runs') or []
    if not entries:
        raise ValueError(f'{path} lists no runs.')
    runs, unstarted = [], []
    for entry in entries:
        if entry.get('run_dir') is None:
            unstarted.append(unstarted_run(entry))
        else:
            runs.append(read_run(entry['run_dir']))
    return manifest, runs, unstarted


def incompleteness(report):
    """Reasons a run may only be listed, never aggregated."""
    status = report.get('status')
    if status != COMPLETE:
        return f'status is {status!r}, not {COMPLETE!r}'
    requested = report.get('sample_count_requested')
    collected = len(report.get('samples') or [])
    if isinstance(requested, int) and collected < requested:
        return f'only {collected} of {requested} requested samples'
    summary = report.get('summary') or {}
    if not isinstance(summary.get('median_bytes'), (int, float)):
        return 'no median in the summary'
    return None


def differences(runs, key):
    return sorted({json.dumps(run['report'].get(key), sort_keys=True) for run in runs})


def guardrails(runs, manifest_power=None):
    """Refuse a comparison the method does not support; return the warnings that remain."""
    reasons, warnings = [], []
    for run in runs:
        median = (run['report'].get('summary') or {}).get('median_bytes')
        if not isinstance(median, (int, float)) or not math.isfinite(median) or median <= 0:
            reasons.append(f"{run['label']}: the summary median is not a positive number of bytes.")
        if run['app'] != 'Paguro':
            continue
        if run['report'].get('verified_release_settings') is None:
            reasons.append(f"{run['label']}: no verified Release build settings; a Debug build cannot support a claim.")
        if run['report'].get('smoke_test'):
            reasons.append(f"{run['label']}: a smoke test validates the collector and does not qualify for a claim.")
    for app in APPS:
        matching = [run for run in runs if run['app'] == app]
        if not matching:
            reasons.append(f'No complete {app} run; a comparison needs matched pairs of both apps.')
        for key in ['version', 'build']:
            values = differences(matching, key)
            if len(values) > 1:
                reasons.append(f"{app} {key} differs between runs: {', '.join(values)}.")
    for key in ['macos', 'model', 'services', 'scenario']:
        values = differences(runs, key)
        if len(values) > 1:
            reasons.append(f"{key} differs across runs: {', '.join(values)}. The workload and hardware must match.")
    counts = {app: len([run for run in runs if run['app'] == app]) for app in APPS}
    if len(set(counts.values())) > 1:
        reasons.append('Unmatched pairs: ' + ', '.join(f'{app} has {count} complete runs' for app, count in counts.items()) + '.')
    sources = sorted({power_source(run['report'].get('power')) for run in runs} |
                     ({power_source(manifest_power)} if manifest_power else set()))
    if len(sources) > 1:
        reasons.append(f"Runs used different power sources: {', '.join(sources)}. Use one power source for every run.")
    elif sources == ['Battery']:
        warnings.append('Every run was measured on battery power. That is one power source, as the method requires, '
                        'but battery state and low power mode change memory behavior; say so beside any number.')
    elif sources and sources != ['AC Power']:
        warnings.append(f'Power source recorded as {sources[0]}; confirm it by hand before using this summary.')
    if reasons:
        raise Refusal(reasons)
    return warnings


def app_stats(entries):
    medians = [entry['report']['summary']['median_bytes'] for entry in entries]
    median = statistics.median(medians)
    return {'median_bytes': median, 'median_mib': mib(median),
            'minimum_bytes': min(medians), 'minimum_mib': mib(min(medians)),
            'maximum_bytes': max(medians), 'maximum_mib': mib(max(medians)),
            'spread_pct': round(100 * (max(medians) - min(medians)) / median, 1),
            'run_count': len(entries)}


def ordered(runs, app):
    """Pair k is the k-th run of each app in start order, so exclusions cannot mispair."""
    return sorted([run for run in runs if run['app'] == app], key=lambda run: str(run['report'].get('started_at') or ''))


def summarize(runs, excluded, reviewed, warnings, swap=None):
    paguro, ferdium = ordered(runs, 'Paguro'), ordered(runs, 'Ferdium')
    pairs, reductions = [], []
    for index, (own, other) in enumerate(zip(paguro, ferdium), start=1):
        mine = own['report']['summary']['median_bytes']
        theirs = other['report']['summary']['median_bytes']
        reduction = 100 * (theirs - mine) / theirs
        reductions.append(reduction)
        pairs.append({'pair': index, 'paguro_bytes': mine, 'paguro_mib': mib(mine),
                      'ferdium_bytes': theirs, 'ferdium_mib': mib(theirs),
                      'reduction_pct': round(reduction, 1),
                      'paguro_label': own['label'], 'ferdium_label': other['label']})
    if len(pairs) < 5:
        warnings = warnings + [f'Only {len(pairs)} matched pairs; the method asks for at least five. '
                               'Treat this as a rehearsal, not evidence for a claim.']
    apps = {'Paguro': app_stats(paguro), 'Ferdium': app_stats(ferdium)}
    spread = max(apps['Paguro']['spread_pct'], apps['Ferdium']['spread_pct'])
    median_reduction = statistics.median(reductions)
    repeatable = all(value > 0 for value in reductions) and median_reduction > spread
    sample = paguro[0]['report']
    ferdium_report = ferdium[0]['report']
    result = {
        'schema': 1, 'scenario': sample.get('scenario'), 'pair_count': len(pairs),
        'reviewed': bool(reviewed), 'warnings': warnings,
        'provenance': {
            'paguro_version': sample.get('version'), 'paguro_build': sample.get('build'),
            'ferdium_version': ferdium_report.get('version'), 'ferdium_build': ferdium_report.get('build'),
            'macos': sample.get('macos'), 'macos_build': sample.get('macos_build'),
            'model': sample.get('model'), 'chip': sample.get('chip'),
            'memory_bytes': sample.get('memory_bytes'), 'services': sample.get('services'),
            'sample_count_requested': sample.get('sample_count_requested'),
            'interval_seconds': sample.get('interval_seconds'),
            'metric': sample.get('metric'), 'power': sample.get('power'),
            'power_source': power_source(sample.get('power')),
            'swap_used_mib_start': (swap or {}).get('start'),
            'swap_used_mib_end': (swap or {}).get('end'),
        },
        'pairs': pairs, 'apps': apps,
        'reduction': {'median_pct': round(median_reduction, 1), 'minimum_pct': round(min(reductions), 1),
                      'maximum_pct': round(max(reductions), 1), 'larger_spread_pct': spread},
        'verdict': REPEATABLE if repeatable else INCONCLUSIVE,
        'runs': [{'app': run['app'], 'label': run['label'], 'run_dir': run['run_dir'],
                  'status': run['report'].get('status')} for run in paguro + ferdium],
        'excluded_runs': excluded,
    }
    result['claim'] = claim_line(result, reviewed)
    return result


NUMBER_WORDS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten']


def service_count_word(services):
    """"five-service" only when five services were measured; the count comes from the run."""
    count = len([name for name in str(services or '').split(',') if name.strip()])
    return NUMBER_WORDS[count] if count < len(NUMBER_WORDS) else str(count)


def claim_line(result, reviewed):
    """The median is the headline; a maximum reduction never is."""
    if result['verdict'] != REPEATABLE:
        return NO_CLAIM
    provenance = result['provenance']
    workload = service_count_word(provenance['services'])
    text = (f"Lower memory footprint than Ferdium {provenance['ferdium_version']} in our {workload}-service idle test "
            f"on {provenance['model']}, macOS {provenance['macos']}: "
            f"{result['reduction']['median_pct']:.1f}% lower (median of {result['pair_count']} matched pairs).")
    return text if reviewed else text + UNREVIEWED


def table(header, rows):
    lines = ['| ' + ' | '.join(header) + ' |', '| ' + ' | '.join(['---:'] * len(header)) + ' |']
    return lines + ['| ' + ' | '.join(row) + ' |' for row in rows]


def swap_line(provenance):
    """Older manifests carry no swap figures; then the line is left out entirely."""
    start, end = provenance.get('swap_used_mib_start'), provenance.get('swap_used_mib_end')
    if start is None and end is None:
        return []
    return [f'- Host swap: {swap_mib(start)} MiB → {swap_mib(end)} MiB']


def excluded_line(run):
    """A run that never started has no directory to name."""
    location = '(no run directory)' if run['run_dir'] is None else run['run_dir']
    return f"- {run['app']}: {run['label']} — {location} ({run['reason']}). Kept and reported, never aggregated."


def render(result):
    provenance = result['provenance']
    lines = [f"# Memory comparison: {result['scenario']} scenario, {result['pair_count']} matched pairs", '']
    for warning in result['warnings']:
        lines += [f'> **Warning:** {warning}', '']
    lines += ['## Provenance', '',
              f"- Paguro {provenance['paguro_version']} (build {provenance['paguro_build']})",
              f"- Ferdium {provenance['ferdium_version']} (build {provenance['ferdium_build']})",
              f"- macOS {provenance['macos']} ({provenance['macos_build']})",
              f"- {provenance['model']}, {provenance['chip']}, {(provenance['memory_bytes'] or 0) / 2**30:.0f} GiB memory",
              f"- Power: {provenance['power_source']} — {' / '.join(str(provenance['power'] or '').splitlines())}",
              *swap_line(provenance),
              f"- Services: {provenance['services']}",
              f"- Sampling: {provenance['sample_count_requested']} samples at "
              f"{provenance['interval_seconds']:g} second intervals per run",
              f"- Metric: {provenance['metric']}", '',
              '## Matched pairs', '']
    lines += table(['Pair', 'Paguro MiB', 'Ferdium MiB', 'Reduction %'],
                   [[str(pair['pair']), f"{pair['paguro_mib']:.1f}", f"{pair['ferdium_mib']:.1f}",
                     f"{pair['reduction_pct']:.1f}"] for pair in result['pairs']])
    lines += ['', '## Per app', '']
    lines += table(['App', 'Median of medians MiB', 'Minimum MiB', 'Maximum MiB', 'Spread %'],
                   [[app, f"{result['apps'][app]['median_mib']:.1f}", f"{result['apps'][app]['minimum_mib']:.1f}",
                     f"{result['apps'][app]['maximum_mib']:.1f}", f"{result['apps'][app]['spread_pct']:.1f}"]
                    for app in APPS])
    reduction = result['reduction']
    lines += ['', '## Reduction', '',
              f"- Median: {reduction['median_pct']:.1f}%",
              f"- Minimum: {reduction['minimum_pct']:.1f}%",
              f"- Maximum: {reduction['maximum_pct']:.1f}%",
              f"- Larger per-app spread: {reduction['larger_spread_pct']:.1f}%", '',
              '## Verdict', '']
    if result['verdict'] == REPEATABLE:
        lines.append(f"{REPEATABLE}: every pair favors Paguro and the median reduction exceeds the larger "
                     f"per-app spread of {reduction['larger_spread_pct']:.1f}%.")
    else:
        lines.append(f"{INCONCLUSIVE}: the advantage is not repeatable across every pair, or it is no larger than "
                     f"the {reduction['larger_spread_pct']:.1f}% run-to-run spread.")
    lines += ['', '## Claim', '', result['claim'], '', '## Runs', '']
    lines += [f"- {run['app']}: {run['label']} — {run['run_dir']} ({run['status']})" for run in result['runs']]
    if result['excluded_runs']:
        lines += ['', '## Excluded runs', '']
        lines += [excluded_line(run) for run in result['excluded_runs']]
    return '\n'.join(lines) + '\n'


def build(args):
    manifest_power = None
    swap = host_swap(None)
    unstarted = []
    if args.manifest:
        manifest, runs, unstarted = load_manifest(args.manifest)
        manifest_power = (manifest.get('environment') or {}).get('power_start')
        swap = host_swap(manifest)
    else:
        runs = [read_run(path) for path in args.reports]
    if unstarted and not args.include_incomplete:
        raise Refusal([f"{run['label']}: never started — the session ended before it "
                       f'({unstarted_error(run)}). Rerun the session, or pass --include-incomplete to list it.'
                       for run in unstarted])
    excluded = []
    for run in list(runs):
        reason = incompleteness(run['report'])
        if not reason:
            continue
        if not args.include_incomplete:
            raise Refusal([f"{run['label']}: {reason}. Rerun the pair, or pass --include-incomplete to list it."])
        excluded.append({'app': run['app'], 'label': run['label'], 'run_dir': run['run_dir'],
                         'status': run['report'].get('status'), 'reason': reason})
        runs.remove(run)
    excluded += unstarted
    if not runs:
        raise Refusal(['No complete runs remain; there is nothing to compare.'])
    warnings = guardrails(runs, manifest_power) + swap_warnings(swap)
    result = summarize(runs, excluded, args.reviewed, warnings, swap)
    return result, (json.dumps(result, indent=2) + '\n' if args.format == 'json' else render(result))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--manifest', type=Path, help='Session manifest from benchmark_session.py')
    source.add_argument('--reports', type=Path, nargs='+', help='Run directories or report.json paths')
    parser.add_argument('--format', choices=['md', 'json'], default='md')
    parser.add_argument('--write', type=Path, help='Also write the summary to this path')
    parser.add_argument('--include-incomplete', action='store_true',
                        help='List incomplete runs as excluded instead of refusing; they are never aggregated')
    parser.add_argument('--reviewed', action='store_true',
                        help='Only after a person has reviewed the raw samples')
    args = parser.parse_args()
    try:
        result, text = build(args)
    except Refusal as refusal:
        parser.exit(1, 'Summary refused:\n' + ''.join(f'- {reason}\n' for reason in refusal.reasons))
    except (ValueError, OSError, json.JSONDecodeError) as error:
        parser.exit(1, f'Summary refused:\n- {error}\n')
    for warning in result['warnings']:
        print(f'Warning: {warning}', file=sys.stderr, flush=True)
    if args.write:
        args.write.expanduser().parent.mkdir(parents=True, exist_ok=True)
        args.write.expanduser().write_text(text)
    print(text, end='')


if __name__ == '__main__':
    main()
