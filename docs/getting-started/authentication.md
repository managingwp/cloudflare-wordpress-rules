---
title: Authentication
description: How the scripts read credentials from ~/.cloudflare.
---

# Authentication

All scripts read credentials from a single config file at `~/.cloudflare`.

You can define either generic (default) credentials or multiple named profiles.
If multiple profiles exist, the scripts offer an interactive menu to choose
which profile to use.

## What you can define

- **Generic (fallback) credentials**
  - `CF_ACCOUNT` + `CF_KEY` (Global API Key auth), or
  - `CF_TOKEN` (scoped API Token auth)
- **Profile-based credentials (recommended)**
  - `CF_ACCOUNT_<PROFILE>` + `CF_KEY_<PROFILE>`
  - `CF_TOKEN_<PROFILE>`

Profiles are any uppercase name you choose (for example `PROD`, `DEV`,
`CLIENT1`). The scripts detect every `CF_(ACCOUNT|TOKEN|KEY)_<PROFILE>` entry and
list them for selection.

## Precedence (highest to lowest)

1. A specific profile passed explicitly with `--cf-profile` (or
   `--cf-auth-profile`).
2. Interactive choice, when multiple profiles are found.
3. Generic credentials: `CF_TOKEN`, or `CF_ACCOUNT` + `CF_KEY`.

## Examples

Minimal (generic) credentials:

```bash
# Uses a single default set for all scripts
CF_ACCOUNT=example@domain.com
CF_KEY=your_global_api_key
# OR
CF_TOKEN=your_api_token
```

Multiple profiles (recommended):

```bash
# Production
CF_ACCOUNT_PROD=prod@company.com
CF_KEY_PROD=prod_global_api_key
# OR
# CF_TOKEN_PROD=prod_api_token

# Development
CF_TOKEN_DEV=dev_api_token

# Client-specific
CF_ACCOUNT_CLIENT1=client1@theircompany.com
CF_TOKEN_CLIENT1=client1_api_token
```

Legacy keys (still supported):

```bash
# Super Page Cache
CF_ACCOUNT_SPC=spc@company.com
CF_TOKEN_SPC=spc_api_token

# Turnstile
CF_ACCOUNT_TS=turnstile@company.com
CF_TOKEN_TS=turnstile_api_token
```

The complete commented template lives in
[`.cloudflare.example`](https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/.cloudflare.example).

## Notes

- Token auth is preferred: it is safer and easier to scope
  (`Zone.Firewall Services:Edit`, and the newer Rulesets permissions described
  in [Migration to the Rulesets API](../guides/migrate-to-rulesets.md#required-api-token-permissions)).
- Some commands do not require authentication and will run without reading
  `~/.cloudflare`:
  - `list-profiles`
  - `print-profile <profile>`
  - `validate-profile <profile>`
  - `list-auth-profiles`

## Passing a profile to a command

```bash
./cloudflare-wordpress-rules -d domain.com -c create-rules default --cf-profile PROD
```

The same flag works on `cloudflare-token.sh` and `cloudflare-turnstile.sh`.
