---
title: Rule generator
description: Build the WordPress WAF rule set (R1–R4) in your browser, then copy it into the Cloudflare dashboard or the Rulesets API.
sidebar_position: 1
---

# Rule generator

The [rule generator](pathname:///generator/index.html) builds the same R1–R4
rule set that `cloudflare-wordpress-rules.sh` deploys, without credentials,
without a Cloudflare API call, and without leaving the browser.

Use it when you want the expressions in front of you before you create rules —
for example to copy them into **Security → WAF → Custom rules** on the
dashboard, to hand a JSON ruleset to somebody else, or to check how much of the
Free-plan limit a rule consumes.

## What it is

- A single static page served from `/generator/` of this site. No build step, no
  service worker, no dependencies.
- Five steps, one idea each, so nothing is buried in a single dense form.

  | Step | What it decides |
  | --- | --- |
  | 1 Start | Which rule set you are reproducing, and the export file. |
  | 2 Trusted traffic | Rule 1: what skips rules 2–4. |
  | 3 Blocking | Rule 2: what is blocked outright. |
  | 4 Challenges | Rules 3 and 4: login/admin, and visitors outside your countries. |
  | 5 Output | Expressions, API JSON and profile JSON. |

- Two sources for the rules. A **builder rule set** fills the fields from a
  preset and rebuilds each rule as you edit; an **exact release** loads the
  expressions a published `profiles/mwp-rules-*.json` shipped, and you edit
  those expressions directly.
- The builder's output is checked against `profiles/default.json` and the beta
  profile by `bash tests/test-generator.sh`, so it matches what the scripts
  deploy. Loaded releases are checked against their own files.
- Client-side only: nothing is uploaded, there is no analytics, and the page
  makes no network requests except for its own preset and version files.

## Colour theme

The header carries a three-way switch: **Auto**, **Light** and **Dark**.

| Choice | What it does |
| --- | --- |
| Auto | Follows the operating system and keeps following it if the setting changes while the page is open. |
| Light | Pins the light palette, whatever the OS says. |
| Dark | Pins the dark palette, whatever the OS says. |

The choice is stored in `localStorage` under `cfwpr.generator.theme.v1` and is
applied before the first paint, so the page never flashes the other palette.
Clearing the site's storage returns it to Auto. Both palettes are contrast
checked; the page also declares `color-scheme` so native controls (checkboxes,
selects, scrollbars) follow the active theme.

## Start from

Step 1 offers two groups in one picker.

**Builder rule sets** are JSON files under
[`website/static/generator/profiles/`](https://github.com/managingwp/cloudflare-wordpress-rules/tree/main/website/static/generator/profiles),
listed in `profiles/index.json`. They fill the option fields; the rules are
rebuilt from those fields.

| Builder rule set | What it does |
| --- | --- |
| `default` | The stable rule set: trusted IPs, integration user agents, the upload-log and xmlrpc blocks, the login challenge, and a CA/US geo challenge. |
| `woocommerce` | The default plus payment-gateway webhook user agents and the two-factor login bypass. |
| `strict-geo` | Blocks visitors outside the allowed countries instead of challenging them, with a trimmed user-agent list. |
| `beta` | Mirrors `profiles/mwp-rules-beta.json`: adds the non-verified Perplexity crawlers and the two-factor login bypass. |

**Exact releases** are read from `profiles/mwp-rules-v*.json` and
`profiles/mwp-rules-beta.json`, listed in the generated
`website/static/generator/profiles/versions.json`. The list names the current
release (`profiles/default.json` decides which one that is), the older ones, and
the staging channel.

Loading a release copies its four expressions in untouched — the character count
and the description hash describe exactly what Cloudflare will receive — and
normalises the envelope to the current v207 shape: `priority` is dropped,
`logging` is defaulted on, and a `skip` rule keeps its action parameters or gains
`{"ruleset": "current"}`. The export never writes `priority` back.

`versions.json` is generated; never edit it by hand:

```bash
bin/build.sh generate-versions   # or bash bin/generate-versions.sh
```

**Reset to source** restores the chosen source and discards edits. Switching
source after hand-editing a rule asks first.

## Step 2–4 options

Each step carries the fields for its own rule. Editing a field rebuilds only
that rule.

| Control | Rule | Notes |
| --- | --- | --- |
| Trusted IP addresses | R1 (skip) | IPv4, IPv6 and CIDR. Duplicates collapse; order is preserved. |
| Use an account IP list | R1 | Emits `ip.src in $list_name` and ignores the inline addresses. The list must already exist in the account. |
| Allowed query strings | R1 | `http.request.uri.query contains "…"`. |
| Allowed user agents | R1 | `http.user_agent contains "…"`. |
| Allow verified bots | R1 | Adds `cf.client.bot`. Verified bots are matched by Cloudflare, not by user agent. |
| Allow two-factor login actions | R1 | Adds the `validate_2fa` / `backup_2fa` / `grace_2fa` bypass used by the beta profile. |
| Blocked paths | R2 (block) | Exact path matches. |
| Block `/xmlrpc.php` | R2 | Skipped when the path is already in the list. |
| Blocked ASNs | R2 | `ip.src.asnum in {…}`. |
| Login/admin challenge | R3 | Managed Challenge on `wp-login.php` and `wp-admin/` (excluding `admin-ajax.php` and the password meter script). |
| Country challenge | R4 | Everyone outside the listed countries gets the chosen action. |

:::warning User agents are spoofable
`http.user_agent contains "…"` matches any client that sends that string. Every
entry in the R1 allow list skips all remaining custom rules, so keep the list
short and prefer `cf.client.bot` where it covers you. This is why non-verified
AI crawlers such as `PerplexityBot` are offered as suggestions rather than
enabled by default.
:::

:::note R1 runs before R4
The skip rule is evaluated first, so an allowed IP, user agent or verified bot
is never challenged by the geo rule. Keep that in mind before combining
`strict-geo` with a broad user-agent list.
:::

## Editing a rule

Every rule step shows its expression in an editor, with the action, `enabled`
and `logging` flags, a `characters / 4096` counter, and the rule's state:

| State | Meaning | What the editor offers |
| --- | --- | --- |
| `fields` | Built from the fields in this step. | Fields rebuild the rule; the expression is editable and becomes `edited`. |
| `loaded` | Read from a release profile. The fields in the step describe *your* builder configuration, not this rule. | **Rebuild from fields** replaces the rule with what the fields produce. |
| `edited` | Typed in by hand. The fields no longer describe it. | **Rebuild from fields** restores the generated expression. |

The two directions never merge: a field edit rewrites its own rule, an expression
edit marks that rule hand-edited, and the stale notice says so. Rebuilding a rule
the fields do not produce (for example rule 4 with the country challenge off)
removes it from the set.

Local checks are deliberately modest: expression length against the 4,096 limit,
the 5-rule cap, and unbalanced parentheses or quotes. Cloudflare's API is the
real parser, and the Output step says so.

## Free-plan limits

The page counts against the limits that matter on the Free plan:

- **5 custom rules.** The rule counter turns red when the configuration needs
  more.
- **4,096 characters per expression** (about 200 IPv4 addresses inline). Every
  editor and rule card shows `characters / 4096`; over-limit rules are flagged
  and highlighted, and the status strip names the step that owns them.

When R1 grows past the limit, switch to an account IP list or split the trusted
sources across rules. Character counts follow the expression exactly as
generated (single-spaced), so they match what the dashboard and API receive.

## Output formats

**Expressions** — one card per rule with the action, `ref`, character count, IP
count and the rule's state (`loaded`, `edited`), plus a copy button. Paste into
*Custom rules → Create rule* and pick the action shown on the card.

**API JSON** — the body for

```bash
curl -X PUT "https://api.cloudflare.com/client/v4/zones/{zone_id}/rulesets/phases/http_request_firewall_custom/entrypoint" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data @ruleset.json
```

This PUT replaces the entire entry point, so merge any rule whose `ref` does not
start with `lmt-` back into the body first.

**Profile JSON** — the same shape as `profiles/*.json`. Save it, add it to
`profiles/`, and deploy it with the script:

```bash
./cloudflare-wordpress-rules -d example.com -c create-rules my-profile
```

## Upgrading without losing local changes

Every generated rule carries a stable `ref` (`lmt-r1` … `lmt-r4`) and a
description that includes the template version and a hash of the expression:

```
lmt-r1 | t207-f89dd20a | Allow trusted IPs, query strings, user agents and verified bots
```

The API tab publishes the matching manifest (`ref`, `hash`, `action`). Before
replacing a ruleset, compare the live rules against it:

| Situation | What to do |
| --- | --- |
| `ref` starts with `lmt-` and the hash matches | Generated and untouched — safe to replace. |
| `ref` starts with `lmt-` and the hash differs | Edited in the account — keep it, or re-apply the edit in the generator. |
| No `lmt-` ref | Client-added rule — never part of the template; keep it. |

## Share links and stored state

**Copy share link** puts the whole configuration in the URL hash, and the same
payload is written to `localStorage` so a reload keeps your work.

- The link carries the source, the option fields, and only the rules you edited
  by hand — everything else is derivable from the source. A configuration you
  never hand-edited therefore stays a short link.
- Links made before the editor existed (`{p, v, o}`) still decode: the preset
  name plus options rebuild the same rules.
- The stored key is `cfwpr.generator.state.v2`; the older
  `cfwpr.generator.options.v1` key is read once and then superseded.
- A link is as sensitive as the rule list: it can contain your trusted IPs.

## Adding a preset

1. Create `website/static/generator/profiles/<name>.json`:

   ```json
   {
     "name": "my-site",
     "label": "My site",
     "description": "Default rules without the geo challenge.",
     "templateVersion": "207",
     "extends": "default",
     "options": {
       "geo": { "enabled": false, "action": "js_challenge", "allowedCountries": [] }
     }
   }
   ```

2. Add `<name>` to `profiles/index.json`.
3. Reload the page. `extends` inherits the parent options; arrays you set are
   used as-is, so repeat the parent values you want to keep.
4. Run `bash tests/test-generator.sh` — the schema, `extends` and manifest
   checks cover every preset listed in the index, and the versions manifest is
   compared with `profiles/`.

You can also export the current configuration (**Download preset**) and load it
back with **Load preset…**; imported presets live only in that browser session.

## Running it locally

The page needs no build. Serve the folder over HTTP so the presets load:

```bash
cd website/static/generator
python3 -m http.server 8080
# open http://localhost:8080/
```

Opening `index.html` directly from disk also works, but browsers block `fetch`
on `file://`, so the page falls back to built-in defaults and says so.

Inside the docs site the same folder is served at `/generator/`:

```bash
npm --prefix website start
# open http://localhost:3000/cloudflare-wordpress-rules/generator/
```

## Privacy

- No account ID, token, zone or visitor data is requested or stored.
- No cookies, no analytics, no third-party scripts, fonts or images.
- Settings are kept in `localStorage` (`cfwpr.generator.state.v2`, which includes
  any hand-edited rules) and the URL hash (`#s=…`), both on your machine. **Copy
  share link** produces a URL containing the configuration, so treat it like the
  rule list itself.
- The colour-theme choice is the only other stored value
  (`cfwpr.generator.theme.v1`); it is not part of the share link.

## Tests

```bash
bash tests/test-generator.sh
```

The suite runs the rule builder under Node (parity against
`profiles/default.json` and `profiles/mwp-rules-beta.json`), loads every release
profile and asserts its expressions survive byte for byte, checks preset schema
and `extends` resolution, the versions manifest against `profiles/`, the theme
switch, the share-link payload (v2 and the v1 fallback), and greps the app for
root-absolute paths, outbound requests, inline styles and analytics. When
`website/node_modules` is installed it also builds the docs site and asserts
`/generator/` is in the output.
