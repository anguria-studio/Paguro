# ADR-0003: Require macOS 26

Date: 2026-08-24

Status: superseded by [ADR-0004](ADR-0004-macos-15.md)

## Context

Paguro needs a native Liquid Glass design.
The reference applications also require macOS 26.

Support for older systems needs a second visual implementation.
It also increases the test matrix.

## Decision

Paguro version 1 requires macOS 26 or later.
The project uses the macOS 26 SDK and Swift 6 strict concurrency.

## Cost

Users on older macOS versions cannot run Paguro.
The first release has a smaller audience.

The team can review this decision after version 1 is stable.
