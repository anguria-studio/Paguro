# ADR-0002: Use public WebKit APIs

Date: 2026-08-24

Status: accepted

## Context

The upstream project used private WebKit selectors to change tracking prevention.
The change helped some third-party sign-in frames.

Private selectors can change without notice.
Their use can also prevent App Store approval.

## Decision

Atoll uses public WebKit APIs only.
It keeps standard WebKit tracking prevention active.

The compatibility matrix will record a service that cannot sign in.
Atoll will not hide this limit with a private selector.

## Cost

Some Microsoft or enterprise sign-in flows can fail.
Atoll can support fewer services than a less strict fork.

This cost protects release stability, privacy, and review options.
