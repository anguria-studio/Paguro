# ADR-0004: Require macOS 15

Date: 2026-08-30

Status: accepted

Replaces [ADR-0003](ADR-0003-macos-26.md).

## Context

ADR-0003 required macOS 26 so the shell could use Liquid Glass without a
second visual implementation. A test build reached a person running macOS
15.7.7, who could not open it. Apple also ended Intel support with macOS 26,
so those Macs stay below the floor for good rather than catching up.

A build at a macOS 14 target reported 23 availability errors and no other
errors. Eight of them belong to scroll and window APIs that arrived in macOS
15, so a macOS 15 floor clears them without any work. The other 15 are Liquid
Glass.

The shell already had the second visual implementation ADR-0003 wanted to
avoid. `ShellGlassStyle.off` draws every surface with material and a tint, and
it ships as a setting.

## Decision

Blatta requires macOS 15 or later.

The shell draws Liquid Glass where the system provides it. Below macOS 26 it
draws the material surfaces the Off style already uses. Toolbar controls,
which had no Off form, take a material capsule.

The island does not depend on macOS 26. It reads `safeAreaInsets`,
`auxiliaryTopLeftArea`, and `auxiliaryTopRightArea`, which are older.

## Cost

Every glass surface needs an availability check and a material counterpart, so
the appearance work happens twice.

Two properties could not hold a macOS 26 type at all, so both changed shape.
`WebToolbarView` no longer passes a `Glass` value to its download control.
The window backdrop holds its glass layer as an optional `NSView`.

The test matrix now covers two systems. A build on macOS 26 still catches a
missing availability check. The compiler reads the deployment target, not the
SDK. It does not catch behavior that only differs at run time.
