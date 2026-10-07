# Changelog

## [0.3.0] - 2026-10-07

- Mail Action Protocol 0.3: strict MAP JSON parsing, RFC 8785 canonicalization and digests, descriptions, type contracts and implementation records, with the reference implementation's rules and messages.
- Extract the one MAP part of a received message, and build the part that carries a description.
- Decide whether a verified DKIM signature qualifies a message for MAP actions.
