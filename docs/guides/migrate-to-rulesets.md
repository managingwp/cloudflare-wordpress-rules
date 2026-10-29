---
title: Migrate to the Rulesets API
description: What changed from Firewall Rules, and how to migrate existing zones.
---

# Migrate to the Rulesets API

The Firewall Rules API and Filters API were **deprecated by Cloudflare on
2025-06-15** and replaced by the **Rulesets API**. This repository has been
fully migrated to the new API.

## What changed

| Aspect | Old (Firewall Rules API) | New (Rulesets API) |
|---|---|---|
| Rule creation | 2 API calls per rule (filter + rule) | 1 API call (expression inline) |
| Profile schema | v2 with `priority` field | v3 with `enabled`/`logging`/`action_parameters` |
| Skip action | `allow` + `bypass` (two actions) | `skip` (one action with config) |
| Custom responses | Not supported | Supported for the `block` action |
| Logging control | Not supported | Per-rule `logging.enabled` |
| Rate limiting | Separate product | Configurable within custom rules |

## Action migration

| Old action | New action | Notes |
|---|---|---|
| `allow` | `skip` with `"ruleset": "current"` | Stops evaluating remaining custom rules |
| `bypass` | `skip` with `"phases": [...]` | Skips specific security products |
| `block` | `block` | Same, with an optional custom response |
| `challenge` / `js_challenge` / `managed_challenge` | Same | No changes needed |
| `log` | `log` | Same |

## One-time migration

If you have existing Firewall Rules on your zones, use the migration tool to
convert them:

```bash
# Preview the migration (rules are applied, old ones preserved)
cloudflare-wordpress-rules -d domain.com -c migrate-to-rulesets

# Full migration with cleanup of old rules and filters
cloudflare-wordpress-rules -d domain.com -c migrate-to-rulesets --delete-old

# Multi-zone migration
cloudflare-wordpress-rules -zf zones.txt -c migrate-to-rulesets
```

The migration tool:

1. Fetches all existing Firewall Rules through the old API.
2. Converts them to Rulesets API format (`allow` → `skip`, priority removed,
   and so on).
3. Applies them to the phase entry point.
4. Optionally deletes the old rules and filters after verification.

## Profile conversion

Convert existing v2 profiles to v3 format:

```bash
bin/convert-profile-v2-to-v3.sh profiles/default.json profiles/default-v3.json
```

## Required API token permissions

For the Rulesets API, make sure your API token includes at least one of:

- `Zone WAF Write` — for zone-level custom rules
- `Zone Rulesets Write` — for zone-level ruleset management
- `Account WAF Write` — for account-level custom rulesets
- `Account Rulesets Write` — for account-level ruleset management

The old `Zone.Firewall Services:Edit` permission may still work for backward
compatibility, but the new permissions are recommended.

## Related

- [Cloudflare's firewall rules upgrade guide](../reference/cloudflare-rulesets/firewall-rules-upgrade.md)
- [Profile format](../reference/profile-format.md)
