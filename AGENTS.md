# AGENTS.md

## Development Documentation

* **Auto-commit after every change.** After completing any code changes (fixes, features, refactors, etc.), automatically create a git commit with a descriptive message using conventional commit format (`feat:`, `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `chore:`). Do not wait for the user to ask — commit immediately after the changes are verified. Print the commit message when finishing the work.
* Search `doc/` folder before creating new documentation files to avoid duplicates.
* After completing code work, suggest testing methods for the change to complete.

## Release Workflow

1. Edit `profiles/mwp-rules-beta.json` with rule changes (IPs, UAs, expressions)
2. Run `bin/build.sh` to regenerate `.md` files and optionally update README changelog
3. Commit changes with `feat:` or `fix:` prefix
4. To publish a numbered release: `bin/release.sh <ver>` (e.g., `bin/release.sh 208`)
5. Commit the release files and tag: `git tag v208`
6. Run `bin/build.sh generate-readme` to update the README changelog from git log

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
