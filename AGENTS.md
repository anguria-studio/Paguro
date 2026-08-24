# Repository instructions

These rules apply to all work in this repository.

## Read before work

Read these files before you change a major feature:

1. `docs/ARCHITECTURE.md`
2. `docs/DESIGN.md`
3. The related file in `docs/features/`
4. `docs/ERRORS.md`
5. `.project/PLAN.md` when that local file exists

## Protect the architecture

- Put deterministic rules in `AtollCore`.
- Keep WebKit and AppKit in the app target.
- Keep one data store for each service account.
- Use public Apple APIs only.
- Keep notification detection separate from presentation.
- Keep the island optional.
- Make `Command-Q` stop all Atoll work.

Do not add private WebKit selectors.
Do not add a hidden browser or an automation browser.
Do not add a remote script system.

## Write clear code

- Use Swift 6 strict concurrency.
- Use value types for pure data.
- Give each type one clear purpose.
- Keep functions short when this improves understanding.
- Explain the reason for a non-obvious decision.
- Do not explain code that already reads clearly.
- Add tests for rules, regressions, and unsafe input.

New comments and documents must use Simplified Technical English where practical.
Old upstream comments can remain until a change touches that code.

## Keep the documents current

Update the architecture document when a dependency direction changes.
Update the design document when a visual rule changes.
Update the feature document when feature behavior changes.
Update the backlog when work starts or ends.

Add a dated entry to `docs/ERRORS.md` after a failed approach teaches a reusable lesson.
Do not use the error log as a list of temporary build errors.

The private file `.project/PLAN.md` contains the work sequence.
Git must ignore the complete `.project` directory.

## Verify each change

Run the smallest useful test first.
Then run the full related test suite.

Use these commands for a full local check:

```sh
xcodegen generate
swift test --package-path Core
xcodebuild -project Atoll.xcodeproj -scheme Atoll -configuration Debug test
scripts/lint_docs.sh
```

If the system does not have a required tool, record that fact in the handoff.
