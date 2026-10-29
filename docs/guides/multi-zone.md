---
title: Multi-zone operations
description: Run one command across many Cloudflare zones.
---

# Multi-zone operations

The script can run a command across multiple zones at once, which is useful for
managing rules on many domains.

## Specifying multiple domains

Use `-d` more than once:

```bash
cloudflare-wordpress-rules -d site1.com -d site2.com -d site3.com -c create-rules default
```

## Using a zones file

Create a text file with one domain or zone ID per line:

```text
# zones.txt
site1.com
site2.com
site3.com
# Comments are supported
example.org  # inline comments too
```

Then reference it with `-zf`:

```bash
cloudflare-wordpress-rules -zf zones.txt -c create-rules default
```

Both methods can be combined:

```bash
cloudflare-wordpress-rules -zf zones.txt -d extra-site.com -c list-rules
```

`zones.txt` is ignored by git. Start from
[`zones.txt.example`](https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/zones.txt.example).

## Skip confirmation

By default the script lists every affected zone and asks for confirmation
before proceeding. Use `-y` to skip the prompt in automation:

```bash
cloudflare-wordpress-rules -zf zones.txt -c delete-rules -y
```

`list-rules` is read-only and data-only, so it never prompts — the zone list is
not written to stdout ahead of the rules.

## Commands supporting multi-zone

- `create-rules` — create rules on all specified zones
- `update-rules` — update rules on all specified zones
- `list-rules` — list rules from all specified zones
- `delete-rules` — delete rules from all specified zones
- `get-settings` — get settings from all specified zones
- `set-settings` — set settings on all specified zones

## Listing rules across zones

`list-rules` is data-only, so the per-zone banners and the final summary are
suppressed and the output can be piped directly. The default table prints a
`domain · zone_id` header for each zone, JSON prints one object per zone, and
CSV prints its header once for the whole run:

```bash
# One compact JSON object per zone
cloudflare-wordpress-rules -zf zones.txt -c list-rules --json \
  | jq -s 'map({domain, count: (.rules | length)})'

# One CSV document with a single header
cloudflare-wordpress-rules -zf zones.txt -c list-rules --csv > rules.csv
```

The exit status is non-zero only when a zone fails hard (authentication or an
HTTP error). A zone with no custom rules reports zero rules and succeeds.

## Output

For every command except `list-rules`, zones are processed sequentially, then a
summary reports:

- total zones processed
- number of successful operations
- number of failed operations
- the list of failed zones, if any

## Related

- [Command reference](../commands/waf-rules.md)
