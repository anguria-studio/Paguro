# ADR-0001: Use Chorus as the code base

Date: 2026-08-24

Status: accepted

## Context

Blatta needs isolated web sessions, downloads, media permissions, hibernation, and WebKit recovery.
These functions contain many platform edge cases.

Chorus already implements and tests much of this work.
Chorus uses the MIT License.

## Decision

Blatta uses Chorus as its code base.
The repository keeps the upstream Git history and license notice.

Blatta will replace the application shell and product design.
It will keep audited WebKit runtime parts where they meet Blatta rules.

## Cost

The first Blatta changes include a large rename.
Some upstream comments and tests still describe old product decisions.

Each touched area needs a Blatta audit.
Upstream changes will require a deliberate merge.
