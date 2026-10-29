---
title: Repository layout
description: What every script, include file and build tool in the repository does.
---

# Repository layout

## Scripts

| File | Description |
| --- | --- |
| [`cloudflare-wordpress-rules.sh`](https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/cloudflare-wordpress-rules.sh) | Create Cloudflare WAF and cache rules (uses the **Rulesets API**) |
| [`cloudflare-token.sh`](https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/cloudflare-token.sh) | Create and manage Cloudflare API tokens (including for the Super Page Cache plugin) |
| [`cloudflare-turnstile.sh`](https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/cloudflare-turnstile.sh) | Create Turnstile widgets |
| [`zones.txt.example`](https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/zones.txt.example) | Example zones file for multi-zone operations |

## Rulesets API include files

| File | Description |
| --- | --- |
| `inc/cf-inc-rulesets.sh` | Rulesets API functions (entry point, CRUD, migration tool) |
| `inc/cf-inc-wp.sh` | Profile-based rule management (v3 compatible) |
| `inc/cf-inc-api.sh` | Core API functions (includes the deprecated Firewall Rules API for backward compatibility) |

## Build and release

| File | Description |
| --- | --- |
| `bin/build.sh` | Unified build orchestrator — regenerate profile markdown, docs pages and the changelog |
| `bin/release.sh` | Promote beta to a numbered rules release (snapshot, version substitution, symlinks) |
| `bin/convert-profile-v2-to-v3.sh` | Convert v2 profiles to the v3 (Rulesets API) format |
| `bin/generate-md.sh` | Render profiles into markdown and refresh the generated docs pages |
| `bin/generate-readme.sh` | Regenerate `CHANGELOG.md` and the docs changelog page |

## Profiles

| Path | Description |
| --- | --- |
| `profiles/default.json` | Symlink to the latest numbered release |
| `profiles/mwp-rules-beta.json` | Staging profile |
| `profiles/mwp-rules-v<NNN>.json` | Release snapshots |
| `profiles/<profile>.md` | Generated rule reference for each profile |

## Documentation

| Path | Description |
| --- | --- |
| `docs/` | This documentation site's content |
| `website/` | Docusaurus configuration, theme and build |
| `website/static/generator/` | Client-side WAF rule generator, served at `/generator/` ([docs](../tools/rule-generator.md)) |
| `AGENTS.md` | Contributor and agent conventions |
| `CHANGELOG.md` | Generated changelog (mirrored on the [changelog page](../changelog.md)) |

## Tests

Offline tests live in `tests/` and need no Cloudflare credentials:

```bash
bash tests/test-beta-readme.sh
bash tests/test-beta-perplexity.sh
bash tests/test-profile-resolution.sh
bash tests/test-print-profile.sh
bash tests/test-docs-site.sh
bash tests/test-generator.sh
```
