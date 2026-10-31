---
title: The v2 script (cwr.sh)
description: The parallel rewrite of the WAF CLI in v2/cwr.sh — scope, layout, guarantees, and how to test it against v1.
---

`v2/cwr.sh` is a from-scratch rebuild of the WAF command line, running beside
`cloudflare-wordpress-rules.sh` on a branch rather than replacing it. It is one
self-contained file with no `inc/` includes, and every human-facing line goes
through the vendored [bash-ui](https://github.com/jordantrizz/bash-ui) library.

## Why a second script

The v1 script grew out of six include files and carries commands that the
Rulesets API has since retired. `cwr.sh` keeps only what the current workflow
needs, so the whole surface fits in one file that can be copied to a server.

v1 remains the supported entry point until v2 reaches parity; nothing in
`cloudflare-wordpress-rules.sh` or `inc/` changes for v1 callers.

## Layout

| Path | Contents |
| --- | --- |
| `v2/cwr.sh` | The script: argument parsing, config and auth, the Rulesets engine, profiles, and output. |
| `vendor/bash-ui/ui.sh` | The pinned UI library, with `ui.sh.sha256` proving it matches the release. |
| `profiles/` | The same rule profiles v1 reads; `cwr.sh` resolves them relative to the script. |
| `tests/test-cwr.sh` | Offline tests: a stand-in `curl` (`tests/cwr/curl`) answers from fixtures. |

`PROFILE_DIR` or `CWR_PROFILE_DIR` overrides the profile directory.

## Commands

Rules: `create-rules`, `update-rules`, `upgrade-default-rules`, `list-rules`,
`delete-rule`, `delete-rules`.

Profiles: `list-profiles`, `print-profile`, `validate-profile`.

Both call styles work, and mean the same thing:

```bash
v2/cwr.sh -d example.com -c create-rules default
v2/cwr.sh create-rules default -d example.com
```

Options: `-d/--domain` (repeatable), `-zf/--zones-file`, `-c/--command`,
`-y/--yes`, `--config`, `--cf-profile`, `--challenge-ttl`,
`--json | --csv | --raw`, `--long`, `--debug`, `--debug-json`, `-h/--help`.

Not in v2: the deprecated filter commands, the ruleset administration commands,
`migrate-to-rulesets`, `update-rule`, `get-settings`/`set-settings`,
`list-auth-profiles`, and the token and Turnstile scripts.

## The two guarantees

**stdout is data; stderr is for people.** `list-rules --json`, `--csv` and
`--raw`, and `print-profile` write to stdout. Everything else — banners, tables,
prompts, errors — goes to stderr through `ui_*`, so `cwr.sh … --json | jq` and
`cwr.sh print-profile default > rules.txt` work and stay clean.

**The API traffic does not change.** `cwr.sh` sends the same Rulesets API
requests, with the same bodies, as v1 for the commands it implements. The test
harness asserts this by running both scripts against the same fixture and
comparing the captured request bodies.

## Testing

```bash
bash tests/test-cwr.sh
```

Checks the help and argument surface, the three profile commands, all five
`list-rules` formats, the `create-rules` payload, the `-y` path through
`delete-rule`, and byte-level parity with v1 for `list-rules --json` and the
`create-rules` POST body. No credentials and no network access are needed.

Run shellcheck without the vendored library:

```bash
shellcheck v2/cwr.sh tests/test-cwr.sh $(git ls-files 'tests/cwr/*')
```

## Keeping bash-ui current

The vendored copy is pinned by version and checksum. `ui.sh` states its own
`UI_VERSION`, so a stale copy is visible in review:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jordantrizz/bash-ui/main/scripts/bash-ui.sh) check
bash <(curl -fsSL https://raw.githubusercontent.com/jordantrizz/bash-ui/main/scripts/bash-ui.sh) update
```

The library is `0.x`: a minor bump may change the `ui_*` API, so treat an update
like any other dependency upgrade.
