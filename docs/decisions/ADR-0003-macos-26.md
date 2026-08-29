# ADR-0003: Require macOS 26

Date: 2026-08-24

Status: accepted for version 1

## Context

Blatta needs a native Liquid Glass design.
The reference applications also require macOS 26.

Support for older systems needs a second visual implementation.
It also increases the test matrix.

## Decision

Blatta version 1 requires macOS 26 or later.
The project uses the macOS 26 SDK and Swift 6 strict concurrency.

## Cost

Users on older macOS versions cannot run Blatta.
The first release has a smaller audience.

The team can review this decision after version 1 is stable.
