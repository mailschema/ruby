# Changelog

## [Unreleased]

## [0.2.0] - 2026-09-26

- First release, for Mail Action Protocol 0.2.
- Parse MAP documents as I-JSON within the core limits, and canonicalize and digest them with RFC 8785.
- Verify a vendored type contract against its pinned digest, and check descriptions, requests, inputs and results against it.
- Build results, state transitions and problems, and apply result retention and approval expiry.
