# AGENTS.md

## Beta Rules Are Always At The Top

`README.md` opens with the current beta ruleset in a generated **Beta Rules (Staging)** section between `<!-- BETA-RULES-START -->` and `<!-- BETA-RULES-END -->`. `bin/build.sh generate-md` renders that block from `profiles/mwp-rules-beta.md`.

Beta edits stay in the staging channel: update `profiles/mwp-rules-beta.json`, regenerate, and commit. Do not bump `VERSION` or run `bin/build.sh generate-readme` until a release; `VERSION`, git tags, `CHANGELOG.md`, and the README changelog change only when `bin/release.sh <ver>` promotes the beta.

## README Release Notes: What's New, Beta, Two Previous Versions

`README.md` presents the newest rules first, in this order:

1. **Beta Rules (Staging)** — the generated block at the top (see above).
2. **What's New in v\<current\>** — release notes for the newest numbered release.
3. **The two previous releases** — `What's New in v\<previous\>`, then `What's New in v\<two-back\>`, newest first.

Rules:

* On a numbered release, add `## What's New in v<ver>` below the beta block and above the previous releases' notes, keep the two previous `What's New` sections, and drop the third-oldest so exactly two previous versions remain.
* `What's New` sections are hand-written summaries of user-visible changes. `bin/build.sh generate-readme` only regenerates the commit changelog between `<!--- CHANGELOG --->` and `<!--- END CHANGELOG --->` at the bottom — it is not a substitute for release notes.
* Beta-only changes get no `What's New` section; they appear in the beta block until promoted to a numbered release.
* Keep the order beta → current → two previous; do not insert a release-notes section anywhere else.

## Development Documentation

* **Auto-commit after every change.** After completing any code changes (fixes, features, refactors, etc.), automatically create a git commit with a descriptive message using conventional commit format (`feat:`, `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `chore:`). Do not wait for the user to ask — commit immediately after the changes are verified. Print the commit message when finishing the work.
* Search the `docs/` folder before creating new documentation files to avoid duplicates.
* After completing code work, suggest testing methods for the change to complete.

## Release Workflow

### Beta channel (no version release)

1. Edit `profiles/mwp-rules-beta.json` with rule changes (IPs, UAs, expressions).
2. Run `bin/build.sh generate-md` to regenerate `profiles/mwp-rules-beta.md` and the **Beta Rules (Staging)** block at the top of `README.md`.
3. Commit the beta profile and generated output with a `feat:` or `fix:` prefix.

### Promoting beta to a numbered release

1. Run `bin/release.sh <ver>` (e.g. `bin/release.sh 208`) to snapshot the beta profile, update the `default.*` symlinks, and bump `VERSION`.
2. Commit the release files: `profiles/mwp-rules-v<ver>.*`, `profiles/default.*`, `VERSION`.
3. Tag the release: `git tag v<ver>`.
4. Run `bin/build.sh generate-readme` to update the README changelog from git log.

## Agents Documentation

* Don't use .cloudflare file, use .cloudflare.example instead to keep secrets from being leaked.
* You can specify a config file using --config flag or CF_CONFIG_FILE environment variable.
* Generate a single line git commit for any changes you make.

## Documentation Files (docs/)

The `docs/` folder contains reference documentation for Cloudflare Rulesets Engine operations:

- **`cf-add-rules-to-a-custom-ruleset.md`** — How to add (or update) rules in an existing custom ruleset using the Cloudflare API `PUT /rulesets/{id}` operation. Covers adding multiple rules at once and updating rules in-place.

- **`cf-api-rulesets.md`** — API reference for Cloudflare Rulesets endpoints. Covers listing account/zone rulesets, fetching a specific ruleset by ID, and pagination via cursor. Includes path/query parameters, request/response schemas, and error types.

- **`cf-deploy-a-custom-ruleset.md`** — How to deploy a custom ruleset by adding a rule with the `execute` action to a phase entry point ruleset at the account or zone level. Includes account-level and zone-level deployment examples.

- **`cf-firewall-rules-upgrade.md`** — Migration guide for upgrading deprecated Cloudflare Firewall Rules (sunset 2025-06-15) to WAF custom rules. Covers differences in actions (`Skip` replacing `Allow`/`Bypass`), evaluation order, API/Terraform resource changes, and `cf-terraforming` migration steps.

- **`cf-ruleset-api-readme.md`** — How to create a WAF custom rule via API using the Rulesets API at the zone level. Includes examples with `challenge` and `block` actions, custom block responses, and next steps for listing/updating/deleting rules.
