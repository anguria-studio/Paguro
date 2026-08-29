# Dependency policy

Status: active

## Scope

Blatta uses Apple system frameworks, BlattaCore, build tools, and GitHub Actions.
Add a third-party runtime package only when a system framework or a small local
implementation cannot meet the requirement safely.

## Update checks

Dependabot checks GitHub Actions each week and Swift packages each month.
It opens a pull request but does not merge it automatically.

Review each update for these items:

- release notes and breaking changes;
- supported macOS and Swift versions;
- new permissions, network access, or executable code;
- license changes and required notice updates;
- lockfile and generated-project changes;
- the complete related test suite.

Security updates take priority. A maintainer can merge a focused security
update after the smallest useful tests and the complete code-quality workflow
pass.

## Adding a dependency

A pull request that adds a runtime dependency must state why Blatta needs it and
why a system API is not suitable. It must pin a reviewed version, add tests at
the adapter boundary, and update `THIRD_PARTY_NOTICES.md` when the license or
bundled material requires a notice.

Do not add dependencies that require private Apple APIs, a remote script
system, a hidden browser, or an automation browser.

## Removing a dependency

Remove a dependency when its feature is gone or a maintained system API can
replace it with less risk. Remove unused permissions and notices in the same
change when their legal terms allow it.
