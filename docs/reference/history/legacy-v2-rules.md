---
title: Legacy v2 rules
description: The archived v2 rule sets kept for reference.
---

# Legacy v2 rules

Before the Rulesets API migration the rules were published as **v2** documents
and JSON profiles. The rule text now lives in
[Legacy v2 expressions](legacy-v2-expressions.md), and the archived profiles
stay in the repository's
[`archive/`](https://github.com/managingwp/cloudflare-wordpress-rules/tree/main/archive)
directory for historical reference only:

| File | Contents |
| --- | --- |
| [`legacy-v2-expressions.md`](legacy-v2-expressions.md) | The full V1 and V2 rule text, moved out of `archive/` |
| `archive/mwp-rules-v1.json` | v1 profile example |
| `archive/mwp-rules-v2.json` | v2 profile with the deprecated `priority` field |
| `archive/mwp-rules-v2-events.json` | v2 profile with event-calendar bot blocking |
| `archive/network-block.json` | Early network block profile |

## Why they are not used

- The v2 format relies on the **Firewall Rules API and Filters API**, which
  Cloudflare deprecated on 2025-06-15.
- v2 profiles use `allow`/`bypass` actions and a `priority` field; the current
  schema uses `skip` and array order.

Use the [profile format reference](../profile-format.md) for the current schema,
and [migrate to the Rulesets API](../../guides/migrate-to-rulesets.md) if you
still have v2 profiles in use.
