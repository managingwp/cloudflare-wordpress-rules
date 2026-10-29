---
title: Release notes
description: What changed in each repository release.
---

# Release notes

Newest first. The [beta channel](reference/beta-rules.md) is listed before
released versions; beta changes appear there until they are promoted to a
numbered rules release.

## Beta channel (staging)

Unreleased rule changes live in `profiles/mwp-rules-beta.json` and are published
on the [Beta rules page](reference/beta-rules.md). They are not part of a
numbered release yet and need no version bump, tag or changelog entry.

## What's New in v2.5.0

- **`list-rules` overhaul** — the default output is now a compact, aligned
  table (position, action, enabled state, rule ID, description) with a zone and
  ruleset summary. The raw entry point JSON is no longer printed by default or
  twice, and startup chatter (`Authenticated…`, `Zone ID found…`,
  `Running…`) no longer pollutes stdout.
- **New output formats** — `--json` (one compact object per zone for `jq`),
  `--csv` (one header plus a row per rule, expressions included), `--raw` (the
  unmodified Cloudflare response) and `--long` (per-rule logging, action
  parameters and full expression). `--table-only` remains as a deprecated alias
  for the default table.
- **Behaviour changes** — a zone with no custom rules now exits `0` instead of
  looking like a failed zone, conflicting format flags exit `2`, and multi-zone
  `list-rules` no longer prompts for confirmation. **The default `list-rules`
  output is no longer raw JSON** — scripts that parsed it should use `--raw` or
  `--json`.
- **Documentation site** — the docs moved into a Docusaurus 3 site (`docs/` and
  `website/`) published from GitHub Actions, with the hand-written release
  notes, generated rule pages and reference material.
- **Rule generator** — a client-side WAF rule generator is published at
  `/generator/` of the docs site, with presets that stay in parity with the
  bundled profiles.
- **Offline tests** — `tests/test-list-rules-output.sh` covers every output
  format, plus docs-site and generator layout/parity checks. No credentials are
  required for any of them.

## What's New in v2.4.3

- **`print-profile` fix** — the v3 Action Parameters block renders again; the jq
  filter no longer fails with `$i is not defined`.
- **Offline tests** — `tests/test-print-profile.sh` and
  `tests/test-beta-readme.sh` run without credentials.
- **Beta rules at the top** — the generated **Beta Rules (Staging)** section is
  refreshed by `bin/build.sh generate-md`.
- **Beta-first workflow** — `AGENTS.md` documents the beta channel, the
  numbered-release promotion path, and the release-notes contract.
- **Beta: Wordfence 2FA** — the login/2FA allow-through in the beta skip rule is
  scoped to Wordfence 2FA actions.

## What's New in v2.4.0

- **Beta channel** — `mwp-rules-beta.json` is the new staging profile for rule
  changes.
- **Default symlink** — `default.json` is a symlink to the latest numbered
  release, selectable as `default`.
- **`bin/build.sh`** — unified build orchestrator (`generate-md`,
  `generate-readme`, or all).
- **`bin/release.sh`** — promote beta to a numbered release with one command.
- **v3 schema** — all bundled profiles now use the v3 Rulesets API format
  natively.

