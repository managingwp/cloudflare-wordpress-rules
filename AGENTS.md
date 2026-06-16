# AGENTS.md

## Development Documentation

* Always create and print out a git commit message for each change made, use the format feat, fix, docs, style, refactor, perf, test, chore
* 
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
