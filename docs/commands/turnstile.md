---
title: cloudflare-turnstile.sh
description: Create and manage Cloudflare Turnstile widgets.
---

# cloudflare-turnstile.sh

Creates and manages Cloudflare Turnstile widgets.

## Usage

```text
Usage: cloudflare-turnstile.sh [command] [options]

Commands:
    create                                Create a turnstile widget
    list                                  List account turnstiles
    delete                                Delete a turnstile
    test-creds                            Test credentials against Cloudflare API

Options:
    -z, --zone <domain>             Zone domain name
    -a, --account <email>           Cloudflare account email address
    -t, --turnstile <sitekey>       Turnstile Sitekey
    -tn, --turnstile-name <name>    Turnstile Name
    -ak, --apikey <apikey>          API Key
  --cf-profile <name>             Cloudflare auth profile from .cloudflare
  --cf-auth-profile <name>        Alias for --cf-profile
    -d, --debug                     Debug mode
    -dr, --dryrun                   Dry run mode
```

## Examples

Create a widget for a domain and give it a recognisable name:

```bash
./cloudflare-turnstile.sh create -z example.com -tn contact-form
```

List the widgets on the account:

```bash
./cloudflare-turnstile.sh list
```

Delete a widget by sitekey:

```bash
./cloudflare-turnstile.sh delete -t <sitekey>
```

Credentials and profiles come from `~/.cloudflare` — see
[Authentication](../getting-started/authentication.md).
