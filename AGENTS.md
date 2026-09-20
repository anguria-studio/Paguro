# Repository instructions

These rules apply to all work in this repository.

## Read before work

Read these files before you change a major feature:

1. `docs/ARCHITECTURE.md`
2. `docs/DESIGN.md`
3. The related file in `docs/features/`
4. `.project/PLAN.md` and `.project/docs/README.md` when these local files exist
5. `.project/docs/DESIGN.md` and `.project/docs/ERRORS.md` when these local files exist

## Protect the architecture

- Put deterministic rules in `PaguroCore`.
- Keep WebKit and AppKit in the app target.
- Keep one data store for each service account.
- Use public Apple APIs only.
- Keep notification detection separate from presentation.
- Keep the island optional.
- Make `Command-Q` stop all Paguro work.

Do not add private WebKit selectors.
Do not add a hidden browser or an automation browser.
Do not add a remote script system.

## Writing rule

Never use em dashes (U+2014) in UI text, comments, documentation,
commit messages, pull request descriptions, or messages to the user.
Use a period, comma, colon, or parentheses instead.

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
Close a ticket in the pull request that completes it.
Do not leave this step for a later cleanup.

- Set the backlog row to `ACTIVE` when work starts, if `.project/docs/BACKLOG.md` exists.
- Before you open the pull request, set the row to `DONE` and write the evidence in it.
- Add the pull request number to the row immediately after you open the pull request.
- Write `Closes ATL-000` in the pull request description, with the real ticket number.
- If the pull request closes without a merge, set the row back to `ACTIVE`.
- A check that only a person can do on hardware goes to the open hardware row.
  It does not keep a completed row open.

The backlog is a private file that Git ignores, so the pull request diff cannot show it.
The pull request template has a box that confirms the update.
Public contributors track unfinished work in GitHub issues and write `Closes #000`.

Add a dated entry to `.project/docs/ERRORS.md` when a failed approach teaches a reusable lesson, if the local file exists.
Keep contributor-facing constraints in the related public feature document.
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
scripts/test_compatibility_fixture.sh
xcodebuild -project Paguro.xcodeproj -scheme Paguro -configuration Debug test
scripts/lint_docs.sh
```

If the system does not have a required tool, record that fact in the handoff.
