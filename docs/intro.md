---
title: Introduction
slug: /
sidebar_position: 1
description: Cloudflare WAF rules, API tokens and Turnstile widgets for WordPress sites.
---

# Cloudflare WordPress Rules

This repository provides bash scripts for creating Cloudflare WAF rules for
WordPress sites, plus helpers for API tokens and Turnstile widgets.

- **[`cloudflare-wordpress-rules.sh`](commands/waf-rules.md)** — create,
  update, list and delete WAF custom rules through the Cloudflare **Rulesets
  API**, across one zone or many.
- **[`cloudflare-token.sh`](commands/token.md)** — create and manage Cloudflare
  API tokens, including tokens for the Super Page Cache for Cloudflare plugin.
- **[`cloudflare-turnstile.sh`](commands/turnstile.md)** — create and manage
  Turnstile widgets.

## Start here

1. [Install the scripts](getting-started/installation.md) and configure
   [`~/.cloudflare`](getting-started/authentication.md).
2. Deploy the stable rules with
   `./cloudflare-wordpress-rules -d example.com -c create-rules default`.
3. Review the [command reference](commands/waf-rules.md) and the
   [profile format](reference/profile-format.md).

## Rules

- [Beta rules (staging)](reference/beta-rules.md) — generated from the beta
  profile on every build.
- [Stable rules](reference/stable-rules.md) — the rules the `default` selector
  deploys today.
- [Profile management](guides/profile-management.md) — how rule changes move
  from beta to a numbered release.
- [Incidents](incidents/index.md) — situations seen on real sites, with the
  rule that stopped each one and the requests it must not block.

## Requirements at a glance

`bash`, `curl`, `jq`, a Cloudflare account, and an API token with the
[Rulesets permissions](guides/migrate-to-rulesets.md#required-api-token-permissions).
