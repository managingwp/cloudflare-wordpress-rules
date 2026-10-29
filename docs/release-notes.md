---
title: Release notes
description: What changed in each repository release.
---

# Release notes

Newest first. The [beta channel](reference/beta-rules.md) is listed before
released versions; beta changes appear there until they are promoted to a
numbered rules release.

To be told when a new release ships, subscribe to the
[release feed](getting-started/release-notifications.md) — the tag is the
release event.

## Beta channel (staging)

Unreleased rule changes live in `profiles/mwp-rules-beta.json` and are published
on the [Beta rules page](reference/beta-rules.md). They are not part of a
numbered release yet and need no version bump, tag or changelog entry.

## What's New in v2.6.0

- **Apply-profile reporting fix** — `create-rules`, `update-rules` and
  `upgrade-default-rules` no longer report `This zone already has  rule(s)` with
  a blank count. The count is read from the entry point response itself, and a
  ruleset that was just created no longer triggers a replace prompt.
- **Rules as tables, not JSON** — before the replace prompt the command prints
  the zone's existing rules as a counted table, and after applying it prints the
  resulting rules the same way. The raw API body and the bare ruleset ID are no
  longer printed.
- **Dated output** — the default table gains a per-rule `UPDATED` column (UTC
  `YYYY-MM-DD HH:MM:SS`) and the summary line shows the ruleset's `last_updated`
  in the same form; `--long` prints a `last_updated:` line per rule.
- **Settings success lines** — `set-settings` reports the change it made, such as
  `Challenge TTL set to 604800 (7d 0h 0m 0s)`, instead of echoing the PATCH body.
- **Offline tests** — `tests/test-apply-profile.sh` covers the new-zone,
  accept, decline, `--yes` and empty-ruleset paths without credentials;
  `tests/test-list-rules-output.sh` asserts the `UPDATED` column.

## What's New in v2.5.1

- **Release notifications** — a new [Release notifications](getting-started/release-notifications.md)
  page explains how to be told about a new release: subscribe to the tag-derived
  `releases.atom` feed, read only `X.Y.Z` tags, and ignore rules-release tags such
  as `v208`.
- **Why not the obvious signals** — the page records why `VERSION` on `main` and
  GitHub's "Latest release"/"Watch → Releases" are not the notification path: a
  rules release rewrites `VERSION` without a tag, and `/releases/latest` lagged six
  tags behind on 2026-10-29.
- **Release workflow** — `AGENTS.md` now states that a release is announced by its
  tag and that the feed is the public notification channel.
- **Offline tests** — `tests/test-docs-site.sh` asserts the page, its sidebar entry,
  the feed URL and the semver filter.

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

