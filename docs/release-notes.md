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

## What's New in v2.6.1

- **Dark mode fix in the rule generator** — the "Allowed user agents" suggestion
  chips (PerplexityBot, GPTBot, ClaudeBot, CCBot, Stripe/, PayPal IPN, and the
  rest) rendered black text on a near-black background, because a `<button>` never
  inherited the page colour. They now follow the palette: 1.21:1 → 12.9:1.
- **Colour theme switch** — the generator header now carries **Auto / Light /
  Dark**. Auto follows the operating system (and keeps following it if you change
  the setting with the page open); Light and Dark pin the palette. The choice is
  stored in `localStorage` and applied before the first paint, so there is no
  flash of the wrong theme.
- **Native controls follow the theme** — the page declares `color-scheme`, so
  checkboxes, the action `<select>`, the file input, scrollbars and progress bars
  stop rendering in light colours on the dark palette.
- **Keyboard and screen-reader fixes** — **Load preset…** is now reachable with
  the keyboard (it was a label around a `hidden` input), the preset buttons keep
  focus when you click one, the notice is announced as a status message, and the
  results list no longer re-announces unchanged messages on every keystroke.
- **Offline tests** — `tests/generator/theme.test.mjs` covers Auto/Light/Dark
  resolution and the boot-script/module contract; `tests/test-generator.sh` now
  also rejects inline styles and asserts the switch, the theme attribute and the
  `color-scheme` declaration.

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
