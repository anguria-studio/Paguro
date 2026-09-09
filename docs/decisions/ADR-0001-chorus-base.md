# ADR-0001: Use Chorus as the code base

Date: 2026-08-24

Status: accepted

## Context

Paguro needs isolated web sessions, downloads, media permissions, hibernation, and WebKit recovery.
These functions contain many platform edge cases.

Chorus already implements and tests much of this work.
Chorus uses the MIT License.

## Decision

Paguro uses Chorus as its code base.
The repository keeps the upstream Git history and license notice.

Paguro will replace the application shell and product design.
It will keep audited WebKit runtime parts where they meet Paguro rules.

## Cost

The first Paguro changes include a large rename.
Some upstream comments and tests still describe old product decisions.

Each touched area needs a Paguro audit.
Upstream changes will require a deliberate merge.
