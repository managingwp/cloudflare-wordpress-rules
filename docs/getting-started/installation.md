---
title: Installation
description: Requirements, installation and the first rule deployment.
---

# Installation

## Requirements

- **bash** 4 or newer
- **curl** and **jq**
- A Cloudflare account with a zone you can edit
- An API token with the [permissions the Rulesets API needs](../guides/migrate-to-rulesets.md#required-api-token-permissions)

## Clone the repository

```bash
git clone https://github.com/managingwp/cloudflare-wordpress-rules.git
cd cloudflare-wordpress-rules
chmod +x cloudflare-wordpress-rules.sh cloudflare-token.sh cloudflare-turnstile.sh
```

The repository also ships short symlinks: `cloudflare-wordpress-rules` and
`cfwpr` both point at `cloudflare-wordpress-rules.sh`.

## Configure credentials

Every script reads `~/.cloudflare`. Start from the commented template:

```bash
cp .cloudflare.example ~/.cloudflare
chmod 600 ~/.cloudflare
```

Then edit the file — see [Authentication](authentication.md) for the profile
format and precedence rules.

## Create rules on a zone

```bash
./cloudflare-wordpress-rules -d example.com -c create-rules default
```

`default` always resolves to the latest numbered release. To try the staging
rules instead, use the `mwp-rules-beta` selector:

```bash
./cloudflare-wordpress-rules -d staging.example.com -c create-rules mwp-rules-beta
```

## Verify what is live

```bash
./cloudflare-wordpress-rules -d example.com -c list-rules
```

Commands that only read local profiles need no credentials at all:
`list-profiles`, `print-profile <profile>`, `validate-profile <profile>`, and
`list-auth-profiles`.

## Next steps

- [Commands reference](../commands/waf-rules.md) — every command and option.
- [Profile management](../guides/profile-management.md) — the beta → release
  workflow for rule changes.
- [Multi-zone operations](../guides/multi-zone.md) — run one command over many
  zones.
