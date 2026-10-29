# Cloudflare WordPress Rules

Bash scripts that create and manage Cloudflare WAF rules, API tokens and
Turnstile widgets for WordPress sites, using the Cloudflare **Rulesets API**.

[![Deploy docs](https://github.com/managingwp/cloudflare-wordpress-rules/actions/workflows/docs.yml/badge.svg)](https://github.com/managingwp/cloudflare-wordpress-rules/actions/workflows/docs.yml)

**Docs** <https://managingwp.github.io/cloudflare-wordpress-rules/> ·
**Rule generator** <https://managingwp.github.io/cloudflare-wordpress-rules/generator/>

<!-- BETA-RULES-START -->
## Beta rules (staging)

Unreleased rule changes live in [`profiles/mwp-rules-beta.json`](profiles/mwp-rules-beta.json);
the generated rules are on the [Beta rules page](https://managingwp.github.io/cloudflare-wordpress-rules/reference/beta-rules).

```bash
./cloudflare-wordpress-rules -d staging.example.com -c create-rules mwp-rules-beta
```
<!-- BETA-RULES-END -->

## Quick start

Requires `bash`, `curl`, `jq`, a Cloudflare account and an API token with
[Rulesets API permissions](https://managingwp.github.io/cloudflare-wordpress-rules/guides/migrate-to-rulesets#required-api-token-permissions).

```bash
git clone https://github.com/managingwp/cloudflare-wordpress-rules.git
cd cloudflare-wordpress-rules
cp .cloudflare.example ~/.cloudflare    # then add your account and token
./cloudflare-wordpress-rules -d example.com -c create-rules default
```

## Rule generator

The [rule generator](https://managingwp.github.io/cloudflare-wordpress-rules/generator/)
builds the same R1–R4 rules in the browser: pick a preset, adjust countries, IPs,
user agents and ASNs, then copy dashboard expressions, `ref`-tagged Rulesets API
JSON (later upgrades keep your own rules) or a v3 profile. Free-plan limits are
counted live; nothing leaves the browser.

## Documentation

| Section | Contents |
| --- | --- |
| [Getting started](https://managingwp.github.io/cloudflare-wordpress-rules/getting-started/installation) | Installation, `~/.cloudflare` authentication |
| [Guides](https://managingwp.github.io/cloudflare-wordpress-rules/guides/profile-management) | Profile workflow, multi-zone runs, skip/block/rate limiting, Rulesets migration |
| [Commands](https://managingwp.github.io/cloudflare-wordpress-rules/commands/waf-rules) | The three scripts and their flags |
| [Rule generator](https://managingwp.github.io/cloudflare-wordpress-rules/generator/) | Open the app — presets, options, outputs; [how it works](https://managingwp.github.io/cloudflare-wordpress-rules/tools/rule-generator) |
| [Reference](https://managingwp.github.io/cloudflare-wordpress-rules/reference/profile-format) | Profile schema, stable and beta rules, Rulesets API |
| [Contributing](https://managingwp.github.io/cloudflare-wordpress-rules/contributing/development) | Build, tests, release workflow, docs site |

## Contributing

Conventions live in [`AGENTS.md`](AGENTS.md); release notes on the
[release notes page](https://managingwp.github.io/cloudflare-wordpress-rules/release-notes).
The offline tests need no credentials:

```bash
bash tests/test-generator.sh && bash tests/test-docs-site.sh
```

Rule changes follow the beta → release flow in the
[profile management guide](https://managingwp.github.io/cloudflare-wordpress-rules/guides/profile-management).
