---
title: cloudflare-wordpress-rules.sh
description: Create and manage Cloudflare WAF custom rules for WordPress sites.
---

# cloudflare-wordpress-rules.sh

Bash script to create and manage Cloudflare WAF rules for WordPress sites
through the Cloudflare API. Supports batch operations across multiple zones.

## Usage

```text
cloudflare-wordpress-rules -d <domain> -c <command> [options]

RULES COMMANDS (Rulesets API)
  create-rules <profile>          Create rules on domain using profile
  update-rules <profile>          Update rules on domain using profile
  upgrade-default-rules           Upgrade MWP default rules on domain
  list-rules                      List rules on domain
  delete-rule <id>                Delete specific rule by ID
  delete-rules                    Delete all rules on domain

PROFILE COMMANDS
  list-profiles                   List available rule profiles
  print-profile <profile>         Print rules from profile
  validate-profile <profile>      Validate profile JSON syntax

RULESET COMMANDS
  list-rulesets                   List rulesets on domain
  get-ruleset <id>                Get specific ruleset by ID
  get-ruleset-fw-custom           Get http_request_firewall_custom ruleset
  ruleset-get-entrypoint          Get the WAF custom rules entry point
  ruleset-add-rule <json>         Add a single rule to the entry point
  ruleset-update-rule <id> <json> Update a single rule in the entry point
  ruleset-delete-rule <id>        Delete a single rule from the entry point
  migrate-to-rulesets [--delete-old]  Migrate old Firewall Rules to Rulesets API

FILTER COMMANDS (DEPRECATED since 2025-06-15)
  list-filters                    List filters on domain
  get-filter <id>                 Get specific filter by ID
  delete-filter <id>              Delete specific filter by ID
  delete-filters                  Delete all filters on domain

SETTINGS COMMANDS
  get-settings                    Get security settings on domain
  set-settings <setting> <value>  Set security setting
    Settings: security_level, challenge_ttl, browser_integrity_check, always_use_https

AUTH COMMANDS
  list-auth-profiles              List available authentication profiles

OPTIONS
  -d, --domain <domain>         Domain to operate on (can be used multiple times)
  -zf, --zones-file <file>      Load zones from file (one per line)
  -y, --yes                     Skip confirmation prompt for multi-zone ops
  -c, --command <cmd>           Command to execute
  --cf-profile <name>           Cloudflare auth profile from .cloudflare
  --cf-auth-profile <name>      Alias for --cf-profile
  --debug                       Enable debug mode
  --json                        list-rules: one compact JSON object per zone
  --csv                         list-rules: CSV rows including expressions
  --raw                         list-rules: unmodified entry point response
  --long                        list-rules: detailed block per rule
  --table-only                  DEPRECATED: alias for the default table
  -dr, --dryrun                 Dry run, don't send to Cloudflare
```

## Examples

```bash
# Create rules on a single domain
cloudflare-wordpress-rules -d domain.com -c create-rules default

# Create rules and force a specific auth profile
cloudflare-wordpress-rules -d domain.com -c create-rules default --cf-profile PROD

# List rules on a domain
cloudflare-wordpress-rules -d domain.com -c list-rules

# List rules as one JSON object per zone (pipe to jq)
cloudflare-wordpress-rules -d domain.com -c list-rules --json

# List rules as CSV, including expressions
cloudflare-wordpress-rules -d domain.com -c list-rules --csv > rules.csv

# Show each rule's logging, action parameters and full expression
cloudflare-wordpress-rules -d domain.com -c list-rules --long

# Print the unmodified Cloudflare entry point response
cloudflare-wordpress-rules -d domain.com -c list-rules --raw

# Deprecated alias for the default table (kept for existing scripts)
cloudflare-wordpress-rules -d domain.com -c list-rules --table-only

# Delete a specific rule
cloudflare-wordpress-rules -d domain.com -c delete-rule 1234567890

# Get security settings
cloudflare-wordpress-rules -d domain.com -c get-settings

# Set security level
cloudflare-wordpress-rules -d domain.com -c set-settings security_level high

# One-time migration from old Firewall Rules to the Rulesets API
cloudflare-wordpress-rules -d domain.com -c migrate-to-rulesets

# Migration + cleanup of old rules
cloudflare-wordpress-rules -d domain.com -c migrate-to-rulesets --delete-old
```

## list-rules output formats

`list-rules` writes data to stdout and diagnostics (errors, warnings, `--debug`) to stderr, so every format can be piped safely. A zone with no rules is a success: it exits 0 with an empty result.

### Table (default)

```text
$ cloudflare-wordpress-rules -d cannaessence.ch -c list-rules
cannaessence.ch · 8e88ca76443f8e20af9c78042803b58d
default · http_request_firewall_custom · 4 rules · version 12 · updated 2026-10-16 20:32:35

#  ACTION             ENABLED  RULE ID                           UPDATED              DESCRIPTION
1  skip               yes      eb107ee2c59741a581214b3e359fffc5  2026-10-16 20:32:35  R1V207 - Allow URI Query, URL, User Agents...
2  block              yes      a8d7034442ea4b76aad7a48b5454dc38  2026-10-16 20:32:35  R2V207 - Block URI Query, URL, User Agents...
3  managed_challenge  yes      85d6b0bce6fa4445bc7d1a2ad87a913c  2026-10-16 20:32:35  R3V207 - Managed Challenge /wp-admin...
4  js_challenge       yes      df7e5f803cf845d7858ea7737b084691  2026-10-16 20:32:35  R4V207 - Challenge Outside of GEO...
```

`UPDATED` is the per-rule `last_updated` Cloudflare reports, shown in UTC as
`YYYY-MM-DD HH:MM:SS` (`?` when a rule carries no timestamp); the summary line
above the table shows the ruleset's own `last_updated` in the same format.
Cloudflare does not expose a creation date for a rule.

`--long` replaces the table with a detail block per rule: id, enabled state,
logging, `last_updated`, action parameters and the full expression.
`--table-only` is a deprecated alias for the default table.

### JSON

One compact object per zone — `domain`, `zone_id`, `ruleset` (id, name, phase, version, last_updated, rule_count) and the `rules` array exactly as Cloudflare returns it:

```bash
cloudflare-wordpress-rules -d cannaessence.ch -c list-rules --json | jq '.rules[].action'
```

For several zones, each zone prints its own object; combine them with `jq -s`:

```bash
cloudflare-wordpress-rules -zf zones.txt -c list-rules --json | jq -s 'map({domain, count: (.rules | length)})'
```

### CSV

A single header row per run, then one row per rule:
`domain,zone_id,position,rule_id,action,enabled,logging,description,expression`.
Fields are quoted by `@csv`, so commas and quotes in expressions and descriptions stay in one field.

```bash
cloudflare-wordpress-rules -d cannaessence.ch -c list-rules --csv > rules.csv
```

### Raw

`--raw` prints the Cloudflare entry point response unchanged, including its `success`, `errors` and `messages` envelope. Use it when debugging the API response itself.

## Applying rules prints the same table

`create-rules`, `update-rules` and `upgrade-default-rules` reuse the table above
instead of dumping the API response:

- **Before replacing** — the command prints `This zone already has N rule(s)`,
  the existing rules table (count, ruleset `updated` line, per-rule `UPDATED`)
  and `The profile contains N rule(s)`, all on stderr, then asks
  `Replace all existing rules? [y/N]`.
- **After applying** — the resulting rules table goes to stdout, preceded by a
  counted success line such as `Replaced 4 rule(s) in ruleset <id>`. A newly
  created entry point prints `Created entry point ruleset <id> with N rule(s)`.
- **`-y` / `--yes`** skips the prompt and the existing-rules preview; the
  resulting table still prints.

Every request failure still exits non-zero and reports the Cloudflare error;
stdout carries the table only.

## Profiles

Profiles are JSON files in `profiles/`. The profile selector is resolved by
**filename first** (`profiles/<selector>.json`), then by the profile's internal
`name` field. That means `default` always targets the latest numbered release,
and any name shown by `list-profiles` is also a valid selector.

- `default` — symlink to the latest numbered release.
- `mwp-rules-beta` — staging profile for rule changes.
- `mwp-rules-v<NNN>` — versioned release snapshots.

The full schema is documented in the
[profile format reference](../reference/profile-format.md). Rule changes follow
the [profile management workflow](../guides/profile-management.md).

## Related

- [Authentication](../getting-started/authentication.md)
- [Multi-zone operations](../guides/multi-zone.md)
- [Migration to the Rulesets API](../guides/migrate-to-rulesets.md)
