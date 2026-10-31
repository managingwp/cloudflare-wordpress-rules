---
title: The v2 script (cfwrv2.sh)
description: The v2 rewrite of the WAF CLI in cfwrv2.sh — scope, layout, guarantees, and how to test it against v1.
---

`cfwrv2.sh` is a from-scratch rebuild of the WAF command line, running beside
the stable `cfwrv1.sh` rather than replacing it. It is one self-contained file
with no `inc/` includes, and every human-facing line goes through the vendored
[bash-ui](https://github.com/jordantrizz/bash-ui) library.

`cfwr.sh` chooses between the two, and `-v2` (or `CWR_VERSION=2`) forces this
script; see [cfwr.sh](../commands/waf-rules.md#choosing-a-version).

## Why a second script

The v1 script grew out of six include files and carries commands that the
Rulesets API has since retired. `cfwrv2.sh` keeps only what the current workflow
needs, so the whole surface fits in one file that can be copied to a server.

v1 remains the supported entry point until v2 reaches parity; nothing in
`cfwrv1.sh` or `inc/` changes for v1 callers.

## Layout

| Path | Contents |
| --- | --- |
| `cfwrv2.sh` | The script: argument parsing, config and auth, the Rulesets engine, profiles, and output. |
| `vendor/bash-ui/ui.sh` | The pinned UI library, with `ui.sh.sha256` proving it matches the release. |
| `profiles/` | The same rule profiles v1 reads; `cfwrv2.sh` resolves them relative to the script. |
| `tests/test-cfwrv2.sh` | Offline tests: a stand-in `curl` (`tests/cwr/curl`) answers from fixtures. |

`PROFILE_DIR` or `CWR_PROFILE_DIR` overrides the profile directory.

## Commands

Rules: `create-rules`, `update-rules`, `upgrade-default-rules`, `list-rules`,
`delete-rule`, `delete-rules`.

Profiles: `list-profiles`, `print-profile`, `validate-profile`.

Both call styles work, and mean the same thing:

```bash
cfwrv2.sh -d example.com -c create-rules default
cfwrv2.sh create-rules default -d example.com
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
prompts, errors — goes to stderr through `ui_*`, so `cfwrv2.sh … --json | jq` and
`cfwrv2.sh print-profile default > rules.txt` work and stay clean.

**The API traffic does not change.** `cfwrv2.sh` sends the same Rulesets API
requests, with the same bodies, as v1 for the commands it implements. The test
harness asserts this by running both scripts against the same fixture and
comparing the captured request bodies.

## Testing

```bash
bash tests/test-cfwrv2.sh
```

Checks the help and argument surface, the three profile commands, all five
`list-rules` formats, the `create-rules` payload, the `-y` path through
`delete-rule`, and byte-level parity with v1 for `list-rules --json` and the
`create-rules` POST body. No credentials and no network access are needed.

Run shellcheck without the vendored library:

```bash
shellcheck cfwrv2.sh tests/test-cfwrv2.sh $(git ls-files 'tests/cwr/*')
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
