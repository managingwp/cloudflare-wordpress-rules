# AGENTS.md

## Beta Rules Are Always At The Top

`README.md` opens with a short generated **Beta rules (staging)** pointer between `<!-- BETA-RULES-START -->` and `<!-- BETA-RULES-END -->`. The full generated ruleset lives in `docs/reference/beta-rules.md`, which is also the first rules page in the docs site. `bin/build.sh generate-md` renders both from `profiles/mwp-rules-beta.md`; never edit either by hand.

Beta edits stay in the staging channel: update `profiles/mwp-rules-beta.json`, regenerate, and commit. Do not bump `VERSION` or run `bin/build.sh generate-readme` until a release; `VERSION`, git tags, `CHANGELOG.md`, and the generated changelog page change only when `bin/release.sh <ver>` promotes the beta.

## Release Notes: Beta, Current, Two Previous Versions

`docs/release-notes.md` presents the newest rules first, in this order:

1. **Beta channel (staging)** — a short section pointing at the generated beta rules page.
2. **What's New in v\<current\>** — release notes for the newest numbered release.
3. **The two previous releases** — `What's New in v\<previous\>`, then `What's New in v\<two-back\>`, newest first.

Rules:

* On a numbered release, add `## What's New in v<ver>` below the beta section and above the previous releases' notes, keep the two previous `What's New` sections, and drop the third-oldest so exactly two previous versions remain.
* `What's New` sections are hand-written summaries of user-visible changes. `bin/build.sh generate-readme` only regenerates the commit changelog between `<!--- CHANGELOG --->` and `<!--- END CHANGELOG --->` — it is not a substitute for release notes.
* Beta-only changes get no `What's New` section; they appear on the beta rules page until promoted to a numbered release.
* Keep the order beta → current → two previous; do not insert a release-notes section anywhere else.
* `README.md` carries a one-line pointer to the release notes; the long-form notes are never duplicated there.

## Development Documentation

* **Auto-commit after every change.** After completing any code changes (fixes, features, refactors, etc.), automatically create a git commit with a descriptive message using conventional commit format (`feat:`, `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `chore:`). Do not wait for the user to ask — commit immediately after the changes are verified. Print the commit message when finishing the work.
* Search the `docs/` folder before creating new documentation files to avoid duplicates.
* New documentation goes into `docs/` — never at the repository root. Only `README.md`, `CHANGELOG.md` and `AGENTS.md` stay at the root.
* After completing code work, suggest testing methods for the change to complete.

## Documentation Site (docs/ + website/)

The documentation is a Docusaurus 3 site. `docs/` is the content directory; `website/` holds the config, theme and build.

```bash
npm --prefix website install     # first run
npm --prefix website start       # dev server on http://localhost:3000/cloudflare-wordpress-rules/
bin/build.sh docs                # production build into website/build
```

Layout: `docs/getting-started/`, `docs/guides/`, `docs/commands/`, `docs/reference/` (including `cloudflare-rulesets/` and `history/`), `docs/contributing/`, plus `docs/release-notes.md` and `docs/changelog.md`. Every page must be registered in `website/sidebars.js` and use front matter (`title`, `description`).

Generated pages — never edit by hand:

| Page | Generator |
|---|---|
| `docs/reference/beta-rules.md` | `bin/build.sh generate-md` |
| `docs/reference/stable-rules.md` | `bin/build.sh generate-md` |
| `docs/changelog.md` | `bin/build.sh generate-readme` |

The build fails on broken internal links and broken Markdown links, so `npm --prefix website run build` is the link check. Site config lives in `website/docusaurus.config.js` (`url`, `baseUrl`, `routeBasePath: '/'`, `onBrokenLinks: 'throw'`).

Publishing runs in `.github/workflows/docs.yml` on pushes to `main` touching `docs/**`, `website/**` or the workflow, and can be dispatched manually. The one-time repository setting is **Settings → Pages → Build and deployment → Source: GitHub Actions**; no `gh-pages` branch is used.

## Rule Generator (website/static/generator/)

A client-side WAF rule generator publishes at `/generator/` of the docs site. It
lives in `website/static/generator/` because Docusaurus copies `static/`
verbatim into the build — it needs no bundler and no workflow of its own.

Layout: `index.html`, `assets/app.css`, `js/` (`rules.js` builder, `ruleset.js`
rule-set model and profile loader, `format.js` renderers, `presets.js` loader,
`versions.js` release list, `share.js` link payload, `limits.js`, `countries.js`,
`theme.js` switch, `theme-boot.js` pre-paint palette, `app.js` UI) and
`profiles/*.json` presets listed in `profiles/index.json`.

Contracts:

* `js/rules.js` is the only place rule expressions are composed. The UI and the
  Node tests import the same module, so the generator and `profiles/*.json`
  cannot drift.
* The page is five steps — Start, Trusted traffic, Blocking, Challenges, Output —
  one `role="tabpanel"` each (`step-start` … `step-output`), wired to the
  `.stepper` tablist. Steps are freely clickable; `Next`/`Back` move one step and
  the sliding `#status-issues` button jumps to the step that owns the first
  error. Keep every form field id stable: the share payload and the tests use
  them.
* Rules are the editable document, not the option form. `js/ruleset.js` owns the
  model: `rulesFromOptions` (builder) and `rulesFromProfile` (release) produce one
  shape with `origin` = `fields` | `loaded` | `manual`. A field change rebuilds
  only its own rule; typing in an expression sets `manual`; **Rebuild from
  fields** replaces that one rule. Never merge the two silently.
* `website/static/generator/profiles/versions.json` is generated by
  `bin/generate-versions.sh` (wired into `bin/build.sh`) from `profiles/`,
  with the rules embedded and `profiles/default.json` deciding `current`. Never
  edit it by hand; `tests/test-generator.sh` regenerates it and compares.
* Loaded releases keep their expressions byte for byte and are exported in the
  current v207 envelope (`priority` dropped, `logging` on, `skip` →
  `action_parameters.ruleset`), so the char counts and description hashes match
  what Cloudflare receives.
* The share payload is v2 — `{k, n, v, o, m}` with `m` holding only hand-edited
  rules — and `js/share.js` still decodes v1 `{p, v, o}` links. `localStorage`
  is `cfwpr.generator.state.v2`, with `cfwpr.generator.options.v1` read once.
* The palette is two token sets in `assets/app.css` selected by `data-theme` on
  `<html>`. `js/theme-boot.js` (a classic script, so it runs before first paint)
  sets that attribute from `localStorage`; it must keep its storage key and
  preference values in sync with `js/theme.js`, which owns the switch.
* `bash tests/test-generator.sh` must stay green. It runs
  `tests/generator/*.test.mjs` (builder parity against `profiles/default.json`
  and `profiles/mwp-rules-beta.json`, release loading and byte-preservation,
  the versions manifest, preset schema, `extends`, renderers, share payloads,
  theme resolution) and greps the app for root-absolute paths, outbound
  requests, analytics, inline scripts and inline styles.
* New presets are JSON files in `website/static/generator/profiles/`, listed in
  `profiles/index.json`; `templateVersion` must equal `profiles/default.json`'s
  `rule_version` (the test enforces it).
* Keep every asset and preset path relative: the app is served from
  `/cloudflare-wordpress-rules/generator/`, not from the domain root.
* All JavaScript stays in external ES modules and no third-party asset, font or
  analytics snippet is ever added — the page ships a `'self'`-only CSP and must
  work offline after first load.
* Do not add a second Pages workflow: `.github/workflows/docs.yml` publishes
  `website/build`, which already contains `/generator/`.
* The documentation page is `docs/tools/rule-generator.md` (registered in
  `website/sidebars.js`); update it when options or outputs change.

## Release Workflow

### Version numbering: rules vs. repository

The rules version and the repository version move independently:

| | **Rules version** | **Repository version** |
|---|---|---|
| Format | numeric, e.g. `208` | semver, e.g. `2.4.3` |
| Lives in | `profiles/mwp-rules-v<ver>.json` / `.md`, `profiles/default.*`, rule metadata | `VERSION`, git tags, `docs/release-notes.md` and the changelog |
| Promoted by | `bin/release.sh <ver>` (snapshots the beta profile) | the squash-release flow below |

A rules release does not imply a repository release, and a repository release does not renumber the rules. `bin/release.sh` also rewrites `VERSION` (`X.Y+1.0`); that is tooling behaviour, not the rules version, and must not be mistaken for a repository release.

### Beta channel (no version release)

1. Edit `profiles/mwp-rules-beta.json` with rule changes (IPs, UAs, expressions).
2. Run `bin/build.sh generate-md` to regenerate `profiles/mwp-rules-beta.md`, `docs/reference/beta-rules.md` and the README beta pointer.
3. Commit the beta profile and generated output with a `feat:` or `fix:` prefix.

### Promoting beta rules to a numbered rules release

1. Run `bin/release.sh <ver>` (e.g. `bin/release.sh 208`) to snapshot the beta profile into `profiles/mwp-rules-v<ver>.*` and repoint the `default.*` symlinks.
2. Commit the rules release files: `profiles/mwp-rules-v<ver>.*` and `profiles/default.*` (plus any regenerated `.md` and docs output).
3. Do not create a repository tag from the rules version — repository git tags track the semver repository version.

### Cutting a repository release

1. Add `## What's New in v<X.Y.Z>` to `docs/release-notes.md` per the release-notes contract above, so the notes land in the release commit.
2. Ensure the tree is clean and the offline tests pass (`bash tests/*.sh`).
3. Run the squash-release flow (`lmt-skills-git-squash-release`; `--bump minor` bumps the patch, e.g. `2.4.2` → `2.4.3`). It updates `VERSION`, squashes everything since the last tag into a `Release X.Y.Z` commit, and tags `X.Y.Z`.
4. A repository release is announced by its git tag: the tag appears in the `releases.atom` feed, which is the public notification channel documented on the [Release notifications](https://managingwp.github.io/cloudflare-wordpress-rules/getting-started/release-notifications) page. A release that is not tagged is not announced.
5. Force-push the branch and tags only after the user explicitly confirms.

## Agents Documentation

* Don't use .cloudflare file, use .cloudflare.example instead to keep secrets from being leaked.
* You can specify a config file using the `--config <file>` flag on `cloudflare-wordpress-rules.sh`; there is no environment variable for it.
* Generate a single line git commit for any changes you make.

## Client Confidentiality in Documentation

Never write a client or prospect domain, hostname, site title or internal host label into `docs/`, `README.md`, `CHANGELOG.md`, profile JSON, generator presets or commit messages. Incident records are written from real work, which is exactly why they leak: the site is the story.

* **Use placeholders.** `site-a`, `site-b` — the closed set documented in `docs/reference/incident-schema.md` — and `example.com` for illustrative URLs.
* **Keep the mapping private.** The real domain-to-placeholder mapping belongs in `zones.txt` (gitignored) or the private tracker, never in the repository.
* **Third-party infrastructure stays.** ASNs, provider address ranges and user-agent strings are safe to publish: they identify the source of an attack, not the client.
* **Brand names are review-level.** `tests/test-incidents.sh` sweeps incident records for hostnames, but a bare site title cannot be detected generically, so read the record before committing it.
* **Commit messages count.** `docs: note the site-a wp-login loop`, never the real domain.

## Documentation Files (docs/)

The `docs/` folder is the documentation site's content directory:

- **`docs/reference/cloudflare-rulesets/add-rules-to-custom-ruleset.md`** — How to add (or update) rules in an existing custom ruleset using the Cloudflare API `PUT /rulesets/{id}` operation. Covers adding multiple rules at once and updating rules in-place.

- **`docs/reference/cloudflare-rulesets/api-reference.md`** — API reference for Cloudflare Rulesets endpoints. Covers listing account/zone rulesets, fetching a specific ruleset by ID, and pagination via cursor. Includes path/query parameters, request/response schemas, and error types.

- **`docs/reference/cloudflare-rulesets/deploy-custom-ruleset.md`** — How to deploy a custom ruleset by adding a rule with the `execute` action to a phase entry point ruleset at the account or zone level. Includes account-level and zone-level deployment examples.

- **`docs/reference/cloudflare-rulesets/firewall-rules-upgrade.md`** — Migration guide for upgrading deprecated Cloudflare Firewall Rules (sunset 2025-06-15) to WAF custom rules. Covers differences in actions (`Skip` replacing `Allow`/`Bypass`), evaluation order, API/Terraform resource changes, and `cf-terraforming` migration steps.

- **`docs/reference/cloudflare-rulesets/ruleset-api-quickstart.md`** — How to create a WAF custom rule via API using the Rulesets API at the zone level. Includes examples with `challenge` and `block` actions, custom block responses, and next steps for listing/updating/deleting rules.

- **`docs/reference/history/`** — Historical documents: the executed Rulesets API migration plan and the archived v2 rules.

- **`docs/reference/profile-format.md`** — The v3 profile schema reference.

- **`docs/reference/beta-rules.md`**, **`docs/reference/stable-rules.md`** — Generated rule references (do not edit by hand).

- **`docs/release-notes.md`** — Hand-written release notes; **`docs/changelog.md`** — generated commit log.

- **`docs/tools/rule-generator.md`** — The client-side rule generator served at `/generator/`: presets, options, Free-plan limits, output formats and upgrade semantics.

- **`docs/incidents/`** — The incident registry: one record per situation observed on a real site, anonymised to a `site-a`-style placeholder, plus the `index.md` table that lists them.

- **`docs/reference/incident-schema.md`** — The incident record contract: required front-matter fields, allowed values, the fixed body sections and the redaction rules.

- **`docs/reference/allowlist-data.md`** — The `ipblocks-ua-qs/` IP, ASN, user-agent and query-string lists, and the JSON document published from them at `/data/ipblocks-ua-qs.json`.

- **`docs/guides/tracking-parameters.md`** — Why blocking on `trk=`, `fbclid`, `gclid`, `msclkid` or `utm_*` blocks real visitors, and what to match instead.

- **`docs/contributing/incident-template.md`** — Copy-paste skeleton for a new incident record.
