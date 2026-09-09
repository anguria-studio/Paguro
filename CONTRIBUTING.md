# Contributing to Blatta

Thank you for your interest in Blatta.

Blatta is an early project.
Open an [issue](https://github.com/tommasoltrz/Atoll/issues) before you make a large change.
This step helps contributors avoid duplicate work.

## Set up the project

1. Install Xcode 26 or later.
2. Install XcodeGen.
3. Run `xcodegen generate` in the repository root.
4. Run `swift test --package-path Core`.
5. Run `scripts/test_compatibility_fixture.sh`.
6. Run the Blatta scheme tests in Xcode.

## Sign a local Debug build

An ad-hoc signed app can run most Blatta tests.
macOS does not allow that app to request notification authorization.
Use an Apple Development identity for notification and permission tests.

1. Copy `Configuration/LocalSigning.xcconfig.example` to
   `Configuration/LocalSigning.xcconfig`.
2. Replace `YOUR_TEAM_ID` with your Apple Developer Team ID.
3. Run `xcodegen generate`.
4. Build Blatta again.

Git ignores `LocalSigning.xcconfig`.
Do not commit a personal team value.

## Make a change

1. Keep the change small and focused.
2. Add a test for each new rule or fixed defect.
3. Update the related feature document.
4. Open an issue when work must continue later.
5. Document reusable constraints in the related feature document.
6. Run the build and all related tests.

Do not edit `Blatta.xcodeproj` by hand.
Edit `project.yml`, and then run `xcodegen generate`.

## Code rules

- Use Swift 6 concurrency checks.
- Keep UI state on the main actor.
- Put pure rules and value types in `BlattaCore`.
- Keep AppKit and WebKit code in the app target.
- Use public Apple APIs only.
- Treat each web message as untrusted input.
- Do not download executable scripts at run time.
- Do not add a dependency without a clear need.
- Use a clear name for each concept.
- Prefer small types with one purpose.

## Documentation rules

Use ASD-STE100 Simplified Technical English where practical.
Use short sentences and active voice.
Use one term for one concept.
Put one instruction in each numbered step.

The Vale rules check a mechanical subset of ASD-STE100.
The rules do not prove full or certified compliance.

Install Vale with Homebrew if you want a local check:

```sh
brew install vale
scripts/lint_docs.sh
```

## Pull requests

Describe the user problem first.
Then describe the solution and its limits.
List the tests that you ran.
Add screenshots for each visible change.

Keep generated files out of a pull request unless the repository tracks them.
