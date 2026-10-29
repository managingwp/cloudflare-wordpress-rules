---
title: Allowlist data
description: The IP, ASN, user-agent and query-string lists in ipblocks-ua-qs, and the JSON document the docs site publishes from them.
---

# Allowlist data

`ipblocks-ua-qs/` holds the plain-text lists that fed the v2 rule set: the IP
addresses of the integrations allowed through the WAF, the ASN of a cloud
provider, the user agents that should never be challenged, and the query
strings that identify a plugin callback.

The lists date from the v2 era and **no profile reads them today** — the rule
expressions in [`profiles/default.json`](profile-format.md) carry their own
copies. They are kept because they are the readable form of that data, and they
are published as JSON below so other tooling can consume them without scraping
text files.

The published document is a convenience export. `profiles/default.json` remains
the authority for what actually ships to a zone.

## Source files

| File | Contents |
| --- | --- |
| `ipblocks-ua-qs/ips-blogvault.txt` | BlogVault / ManageWP backup IP addresses |
| `ipblocks-ua-qs/ips-wp-umbrella.txt` | WP Umbrella addresses, including one IPv6 range |
| `ipblocks-ua-qs/user-agents.txt` | Integration user agents (Zapier, WP Umbrella, ShortPixel, …) |
| `ipblocks-ua-qs/query-strings.txt` | Plugin callback query strings (WooCommerce ShipStation) |
| `ipblocks-ua-qs/asn.txt` | AS number and label, `396982 # Google Cloud Compute Engine` |

Format: one entry per line, `#` starts a comment, blank lines are ignored,
surrounding whitespace is trimmed. `ipblocks-ua-qs/R2.json` and
`ipblocks-ua-qs/build.sh` are the v2 profile builder those lists fed; they are
historical and are not used.

## The published JSON

`bin/export-ipblocks.sh` renders the lists into
`website/static/data/ipblocks-ua-qs.json`, which the docs build publishes at:

```text
https://managingwp.github.io/cloudflare-wordpress-rules/data/ipblocks-ua-qs.json
```

Fetch it with anything that speaks HTTP:

```bash
curl -s https://managingwp.github.io/cloudflare-wordpress-rules/data/ipblocks-ua-qs.json \
  | jq -r '.ips[]'
```

### Fields

| Field | Type | Contents |
| --- | --- | --- |
| `schema_version` | integer | `1`. Changes only when the shape changes. |
| `name` | string | `ipblocks-ua-qs`. |
| `description` | string | What the document is, and that profiles remain the authority. |
| `source_dir` | string | `ipblocks-ua-qs/`. |
| `sources` | array | The five source filenames the export is built from. |
| `ips` | array | Plain addresses — no CIDR, no IPv6. Ready for `ip.src in { … }`. |
| `networks` | array | Anything carrying `/` or `:` — CIDR blocks and IPv6 ranges. |
| `asns` | array | Objects with `asn` (number) and `label` (string). |
| `lists` | object | Per-file arrays: `ips_blogvault`, `ips_wp_umbrella`, `user_agents`, `query_strings`. |

Arrays are sorted and de-duplicated, so two runs of the exporter produce
byte-identical output. There is no timestamp for that reason.

```json
{
  "schema_version": 1,
  "ips": ["88.99.145.111", "195.201.197.31"],
  "networks": ["2001:BC8:2B7F:801::292/64"],
  "asns": [{ "asn": 396982, "label": "Google Cloud Compute Engine" }],
  "lists": {
    "user_agents": ["Better Uptime Bot", "Zapier"],
    "query_strings": ["wc-api=wc_shipstation"]
  }
}
```

## Regenerating

After editing a source list, rebuild the export and run its test:

```bash
bin/export-ipblocks.sh
bash tests/test-ipblocks-data.sh
```

The test fails when the committed JSON and the source lists disagree, so a
hand-edited export cannot drift: `test-ipblocks-data.sh` checks source parity
and regenerates to a temporary file to diff against the committed one.

## Related

- [Profile format](profile-format.md) — the profile that carries the live rule
  expressions.
- [Stable rules](stable-rules.md) — the rules the `default` selector deploys
  today, including the allow rule these lists used to feed.
