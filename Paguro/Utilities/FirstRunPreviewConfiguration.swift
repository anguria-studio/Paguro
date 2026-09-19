#if DEBUG
import Foundation

/// Forces the first-run home screen, so the screen can be looked at after the
/// first service exists.
///
/// The whole file is inside `DEBUG`, like `IslandPreviewNotifications`. Only
/// the app target defines `DEBUG`, in the `Debug` and in the custom
/// `Compatibility` configuration, and a Release build compiles nothing from
/// this file. The argument string therefore cannot reach a released binary, and
/// `scripts/build_release.py` scans each Release build for it.
///
/// The argument changes the screen alone. It writes no value, so a workspace
/// full of services is unchanged when the app starts again without it.
enum FirstRunPreviewConfiguration {
    static let launchArgument = "--paguro-first-run-preview"

    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains(launchArgument)
    }
}
#endif
