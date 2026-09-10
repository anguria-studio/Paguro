# Performance comparisons

Status: collector, session driver and summary ready; recorded sessions are kept privately in .project/benchmarks/RESULTS.md; no result is published; hibernated scenario pending

## Purpose

Measure Paguro against named application versions before making a comparison
on the website. WebKit alone does not prove lower memory use, faster responses,
or longer battery life.

Start with memory footprint. Test CPU activity, launch time, service switching,
and battery use separately. A memory result cannot support a speed or battery claim.

## A matched workload

1. Use the same Mac, macOS build, power source, power mode, screen, and window size.
2. Use current stable native builds of the comparison apps. Run Paguro in Release
   without Xcode or a debugger. Record each version and build number. Confirm that
   none runs through Rosetta unless that is the intended comparison.
3. Sign in to the same services and accounts in both apps — at least five. Use the same pages,
   selected service, content, and zoom. Sign-in pages are not an equivalent workload.
4. Match notification, preload, content-blocking, extension, and hibernation settings.
   Record any setting that cannot be matched. Include relevant user-agent differences.
5. Open each service once and let loading complete. Check that each service works.
   Do not treat a failed page, missing service, or silently sleeping tab as a memory win.
6. Run one app at a time. Close unrelated high-load apps, stop builds and downloads,
   and wait for the Mac to settle. Use the same foreground/background state in each run.
   Host swap must be near zero before a run, because `footprint` excludes swapped-out
   pages and a pressured host under-reports whichever app lost pages to swap;
   `scripts/benchmark_session.py` refuses to start above 1 GiB of swap in use
   (override with `--allow-swap`) and records swap at both ends of every session.
7. Wait two minutes after all pages settle, then measure for five minutes. Avoid
   calls, playback, typing, and manual navigation during this idle-memory scenario.
8. Repeat at least five matched pairs. Alternate or randomize app order. Keep all
   runs, including failures and interruptions, and explain any exclusions.

The two primary scenarios are:

- **Awake:** all signed-in services remain loaded, with hibernation disabled. This tests
  the cost of keeping the same services available for live activity.
- **Hibernated:** the selected service stays awake and every other service has fully
  hibernated. Confirm their state before sampling. Record that
  those services cannot provide the same live notifications until they wake.

Rambox and Ferdium also offer hibernation. Compare equivalent states. A separate
default-settings comparison is useful, but label it separately and record the defaults.

An empty-window measurement is only an application-shell baseline. Do not present
it as a signed-in service workload. Do not clear account data or copy sessions between apps.

## Memory collection

From the repository root, run:

```sh
python3 scripts/benchmark_memory.py \
  --bundle-id studio.anguria.paguro \
  --label 'Paguro awake run 1' \
  --scenario awake \
  --services 'List the service names here' \
  --notes 'Record selected service, window size, visibility, and settings here'
```

For Ferdium, use `--bundle-id org.ferdium.ferdium-app` and a matching run label.
Use `--scenario hibernated` for the second scenario. The defaults collect 31
samples at ten-second intervals, covering approximately five minutes.

The script uses the macOS `lsappinfo` process coalition to include helper processes,
then reads the group's aggregate `total footprint` from Apple's `footprint` tool.
WebKit helpers commonly have `launchd` as their parent. A child-process walk or a
measurement of the main app alone can omit most of Paguro's memory.

Inspect each app's coalition and the raw process list before accepting a result.
Cross-check grouping with Activity Monitor or Instruments, especially when an app
has a background helper outside its main coalition. The script does not assume
that every process called WebKit belongs to Paguro.

The tool rescans membership before each sample. It stops if the app restarts,
membership changes during collection, a process is missing, or `footprint` reports
an error or warning. It saves partial runs as incomplete. A process change between
samples is recorded through that sample's process list. Do not select only low-memory
samples from an unstable run; settle the app and repeat the complete pair.

Results go to unique folders under ignored `.project/benchmarks/`.
Each folder contains raw `footprint` JSON and a report.
The report records hardware, OS, app version, power settings, sample times, and process IDs.
It also records median, minimum, and maximum footprint in bytes.
MiB means bytes divided by 1,048,576. This metric is not virtual memory, a sum of
RSS columns, an allocation count, or installed application size.

The script does not launch, close, configure, or sign in to any app. Run labels and
notes should contain service names, not account identifiers or message content.
Review raw results before sharing. No result is published automatically.

Known Debug builds are rejected unless both `--scenario smoke` and `--smoke-test`
are supplied. This check is a convenience, not proof that another build is Release.
Verify the build and debugger state yourself. A smoke test validates the collector;
it does not qualify for a performance claim.

## Session orchestration

`scripts/benchmark_session.py` automates steps 6 to 8 of the matched workload: one app
at a time, settle, measure, then the same for the other app, repeated as matched pairs
with the order alternating each pair. From the repository root, run:

```sh
python3 scripts/benchmark_session.py --scenario awake --pairs 5 \
  --services 'List the service names here' \
  --paguro-app /path/to/Release/Paguro.app \
  --release-build-settings .project/benchmarks/release-build-settings.json
```

Each run launches the app, waits two minutes, takes two membership probes twenty
seconds apart, calls `scripts/benchmark_memory.py` as a subprocess, quits the app with
`osascript`, and cools down. Use `--dry-run` first: it performs the read-only checks and
prints every command the session would run, without launching or writing anything.

The session refuses to start on battery power without `--allow-battery`, while Xcode is
running, or while either app is already running; a stale Debug build shares Paguro's
bundle id, and measuring it would not measure the Release build. After launching Paguro
it compares the running bundle path against `--paguro-app` and stops on any mismatch.
It stops if process membership changes between the two probes, if `--min-processes` is
not met, if the collector exits non-zero or prints no saved report, or if an app does
not quit within forty-five seconds. It never retries, never skips a pair, and never
substitutes a result. `caffeinate` keeps the Mac awake for the session only.

The manifest at `.project/benchmarks/session-<timestamp>-<scenario>.json` lists every
planned run before the first launch, and is rewritten after each run and on exit. It
records the scenario, services, environment, power at both ends, and for each run the
pair, order, app, label, run directory, status, and error. An aborted session keeps its
completed runs and names the failure; keep those runs and explain any exclusion.

The script launches and quits the apps. It never signs in, never changes a setting, and
never kills a process: when an app will not quit, it says so and asks you to quit it
yourself, then start a new session.

## Reporting

Calculate a median for each run, then summarize those medians and the observed
range across the five matched pairs. Preserve all raw samples and publish the
method, app versions, workload, settings, date, and hardware beside a comparison.

For a lower-memory result, calculate the reduction as:

```text
100 × (competitor footprint − Paguro footprint) / competitor footprint
```

Only use a percentage if the advantage is repeatable across the paired runs and
larger than ordinary run-to-run variation. Report a mixed or inconclusive result
as such. Do not select a maximum reduction as the headline.

A supported claim could say: “Lower memory footprint than Ferdium [version] in
our [N]-service idle test on [Mac and macOS version].” [N] is the number of
services signed in with real content in both apps during that session; the
summary derives it from the run's service list. Add the measured number
only after review. Do not generalize this to all Electron apps or all workloads.

Use Instruments for later CPU, launch, and response-time measurements. Battery
claims need a separate controlled energy or battery test with equal display and
network conditions; an idle CPU percentage is not enough.

## Summarising a session

Once a session has finished, summarize it in one step. From the repository root, run:

```sh
python3 scripts/benchmark_summary.py \
  --manifest .project/benchmarks/session-<timestamp>-<scenario>.json \
  --write .project/benchmarks/session-<timestamp>-<scenario>-summary.md
```

Use `--reports <run directory> …` for an ad-hoc set without a manifest; the app comes from the
bundle identifier and pair `k` is the `k`-th run of each app in start order. Add `--format json`
for the same fields as data. The tool reads saved reports only. It never launches, configures,
or measures an app.

The summary refuses, rather than guesses, when the method has been broken: any aggregated run
that is not `complete-unreviewed`, any run with fewer samples than it requested, a Paguro run
without verified Release build settings or from a smoke test, a version or build that changes
between runs of one app, a macOS version, model, scenario, or service list that changes across
runs, an unequal number of runs per app, or runs split between AC power and battery. Each
refusal names the run, so the fix is to repeat that pair rather than to drop it. `--include-incomplete`
lists excluded runs with their reasons; it never lets them into the arithmetic. A session measured
entirely on battery is allowed and warned about prominently, as is a session shorter than five pairs.

The verdict is `repeatable` only when every pair favors Paguro and the median reduction is larger
than the wider of the two apps' run-to-run spreads; otherwise it reports `mixed or inconclusive`
and supports no comparison. The headline is always the median reduction, never the largest pair.

The claim line carries ` — unreviewed; do not publish` until a person has read the raw samples and
process lists and passed `--reviewed`. That flag changes the suffix and nothing else. Publishing
the number still needs the method, versions, workload, settings, date, and hardware beside it.

## Verification and references

Run `python3 scripts/test_benchmark_memory.py`, `test_benchmark_session.py` and
`test_benchmark_summary.py` from `scripts/` for grouping, partial-sample, session and
summary regressions. No application behavior changes are required for this collector.

- [Apple Instruments tutorials](https://developer.apple.com/tutorials/instruments)
- [Apple performance and metrics](https://developer.apple.com/documentation/xcode/performance-and-metrics)
- [Rambox hibernation settings](https://support.rambox.app/support/solutions/articles/42000066414-how-to-hibernate-)
- [Ferdium features](https://ferdium.org/)
