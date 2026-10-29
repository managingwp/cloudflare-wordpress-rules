---
title: cloudflare-token.sh
description: Create and manage Cloudflare API tokens, including Super Page Cache tokens.
---

# cloudflare-token.sh

Creates and manages Cloudflare API tokens, including tokens for the Super Page
Cache for Cloudflare WordPress plugin. Supports account-owned tokens.

## Usage

```text
Usage: cloudflare-token.sh [command] [options]

Commands:
    create-token <domain> <token-name>    Create API token for domain
    list                                  List account tokens
    test-creds                            Test credentials against Cloudflare API
    test-token <token>                    Test created token against Cloudflare API

Options:
    -z, --zone <zoneid>           Set zone ID
    -a, --account <email>         Cloudflare account email address
    -t, --token <token>           API Token to use
    -ak, --apikey <apikey>        API Key to use
  --cf-profile <name>           Cloudflare auth profile from .cloudflare
  --cf-auth-profile <name>      Alias for --cf-profile
    -d, --debug                   Debug mode
    -dr, --dryrun                 Dry run mode
```

## Examples

Create a scoped token for a zone and name it:

```bash
./cloudflare-token.sh create-token example.com super-page-cache
```

List the tokens on the account:

```bash
./cloudflare-token.sh list
```

Check that stored credentials work:

```bash
./cloudflare-token.sh test-creds
```

Check a token you already have:

```bash
./cloudflare-token.sh test-token <token>
```

Credentials and profiles come from `~/.cloudflare` — see
[Authentication](../getting-started/authentication.md).
