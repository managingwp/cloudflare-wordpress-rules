## test: assert the release notifications page documents the tag feed
## docs: point release notes and release workflow at the feed
## docs: add release notifications page for the tag feed
## Release 2.5.0
* (c059060) docs: add v2.5.0 release notes
* (9fc29db) fix: keep the list-rules stdout stream free of multi-zone confirmation prose
* (73e09b7) docs: document the list-rules table, json, csv, raw and long options
* (cfdf149) test: cover list-rules table, long, json, csv and raw output offline
* (d62a7af) feat: give list-rules a data-only table plus json, csv, raw and long modes
* (62e219c) docs: link the generator app from the README documentation table
* (7c503a9) docs: tighten README and surface the rule generator
* (960d14e) feat: add static WAF rule generator under the docs site
* (dc41271) docs: regenerate changelog for the docs site migration
* (07761c2) test: enforce the docs-site layout and slim README contracts
* (322d27d) ci: deploy the docs site to GitHub Pages
* (aa41282) feat: generate docs pages and README pointer from profiles and changelog
* (4bb13bb) docs: slim README to a docs-site entry point
* (1aa7bfd) docs: migrate documentation into the Docusaurus site
* (0ed7a91) feat: scaffold Docusaurus docs site in website/
* (1207ec4) test: add offline Perplexity allowlist regression test
* (e4857aa) docs: regenerate beta profile output for the Perplexity allowlist
* (124807c) feat: allow Perplexity crawlers through beta R1 skip rule
* (ca0443a) docs: distinguish rules version from repository version
## Release 2.4.3
* (c7b5ea0) docs: document README release-notes contract and add v2.4.3 notes
* (a6ae39f) test: add offline beta README regression test
* (b49ffcf) docs: document beta-first workflow in AGENTS.md
* (539af73) docs: document README beta block in build tooling
* (c6c3ee4) feat: generate beta rules block at top of README
* (a3ca63e) fix: scope beta login allow-through to Wordfence 2FA actions
* (1fa1ecd) revert: undo over-broad 2FA/login allow-through in beta skip rule
* (58274bc) test: add offline print-profile regression test for action parameters
* (98dc68b) fix: correct jq $i interpolation in cf_print_profile action parameters
* (f19c578) feat: add login/2FA allow-through to beta skip rule
## Release 2.4.2
* (fee03d9) docs: document default profile selector and name lookup
* (546b244) test: add offline profile resolution tests
* (357764a) feat: resolve profiles by filename or internal name
* (1f83265) feat: add profile resolver and display-name helpers
* (4fba9f1) chore: add /plans to .gitignore for external plans
## Release 2.4.1
* (72bbf48) feat: add Confirming Challenge Passage prompt with 604800 default and y/c/n options
* (d221c26) chore: added .gitignore
* (3eaac5f) feat: normalize -d domain args to bare domain (strip scheme, path, www)
## Release 2.4.0
* (940edcc) (HEAD -> main) fix: preserve .md symlinks in generate-md.sh
* (32e1eb1) docs: update AGENTS.md, README.md, TODO.md for v2.4.0 workflow
* (e60a75b) chore: remove stale mwp-rules-v206 profile
* (44e99cc) fix: skip symlinked JSON files in generate-md.sh
* (04144ac) feat: create bin/release.sh for beta→release promotion
* (684a7d4) feat: create bin/build.sh unified build orchestrator
* (c2ac306) chore: update .gitignore to allowlist bundled profiles
* (ec18520) feat: create v207 release, default symlinks to latest stable
* (e1efdb4) feat: replace mwp-rules-latest with mwp-rules-beta (v3 schema)
* (29975f9) perf: combine challenge TTL + rules creation into single pass per zone
* (f63009e) (origin/main, origin/HEAD) chore: added zones.txt to .gitignore
* (87f0188) feat: add --challenge-ttl argument to set Challenge Passage TTL when creating rules
## Release 2.3.2
* (d413add) (HEAD -> dev, origin/dev) feat: show current Challenge Passage setting before prompting to change
* (73885f3) feat: copy mwp-rules-latest to mwp-rules-v206
* (d72d884) chore: update mwp-rules-latest.json and regenerate default.md
* (f7fe977) docs: regenerate mwp-rules-latest.md from updated JSON
* (3bdc75d) fix: add explicit rule positions and upgrade default profile to v3
## Release 2.3.1
* (bb8b32e) feat(create-rules): add interactive Challenge Passage prompt before rule creation
* (aa3c276) feat: add Y/N confirmation before replacing existing rules in cf_ruleset_apply_profile
* (932e4a2) fix: _success now writes to stderr to prevent stdout contamination in command substitutions
* (27e6a50) docs: Updated TODO.md
## Release 2.3.0
* (24fcd0d) docs: update README and CHANGELOG for v2.3.0 release
* (de92844) docs: fill in missing CHANGELOG entries for v2.2.2 through v2.2.5
* (64e50fa) chore: removed debugging
* (a395adf) fix: add action_parameters back for skip action only
* (b2d2ba5) fix: minimal payload for PUT replace-all endpoint
* (a26e6b9) fix: strip enabled and logging fields from API payload
* (f97fa00) fix: support numeric profile selection and case-insensitive --cf-profile matching
* (05ef64a) chore: add debug logging for PUT payload in cf_ruleset_replace_all_rules
* (62a8cfd) fix: strip empty action_parameters from API payload
* (1835ed5) fix: strip internal rule_number/rule_version fields from API payload
* (64b6ff6) fix: suppress stdout from cf_ruleset_get_entrypoint in _cf_ruleset_get_or_create_entrypoint
* (8315b0a) feat: Phase 8 - Documentation & Testing
* (2d71bfc) feat: Phase 7 - Deprecation & Cleanup, Migration Tool
* (ed42f4c) feat: Phase 6 - New Rulesets API features
* (94d146e) feat: Phase 5 - CLI Command Migration to Rulesets API
* (22a9d99) feat: Phase 4 - Rule Management Migration to Rulesets API
* (5d10ed4) feat: Phase 3 - Profile Format v3
* (b82bc9d) feat: Phase 2 - Core Rulesets API functions
* (bcdb312) feat: Phase 1 - Foundation for Rulesets API migration
* (dbc2a5b) refactor: Move cf-inc*.sh files into inc/ directory and update all source paths
* (7b082a9) docs: Updated AGENTS.md
* docs: update README and CHANGELOG for v2.3.0 release
* docs: fill in missing CHANGELOG entries for v2.2.2 through v2.2.5
* chore: removed debugging
## Release 2.2.5
* (c2b8936) docs: Updated AGENTS.md
* (31582ce) docs: Updated TODO.md
* (a0f3bf0) chore: Renamed doc files
* (3fe90eb) docs: Added Cloudflare docs.
* (f36c768) chore: added cfwpr symlink
* (5a06623) fix: suppress list-rules table-only startup chatter and restore no-rules
* (74046fc) fix: add --table-only mode for list-rules output while preserving errors
* (bc51b87) feat(auth): add --cf-profile/--cf-auth-profile to select Cloudflare auth profile across scripts
* (657224c) fix: Added auth gate so auth is done when valid command is entered
## Release 2.2.4
* fix: Strips inline comments from Cloudflare config loader
## Release 2.2.3
* fix: Added challenge-ttl possible values
* refactor: update authentication environment variable format
* fix: load config before listing auth profiles
* feat: allow list-auth-profiles to use custom config file parameter
* docs: Created AGENTS.md
* test: Test file for .cloudflare
* docs: Updated AGENTS.md
* feat: add --config argument to use alternative .cloudflare file for all commands
* fix: Unify authentication profile display format
* Fix: Remove overly restrictive dash validation, mask credentials in debug output, prioritize Account API auth over Token auth
## Release 2.2.2
* * Created mwp-rules-latest.json for the latest bleeding edge rules.
* * Added Infusionsoft to mwp-rules-latest.json
## Release 2.2.1
* * Added Screaming Frog to allow list.
* * Updated rules to v205
## Release 2.2.0
* * improvement: Added color to the usage screen
* * fix Updated CHANGELOG.md and README.md as well as profiles/mwp-rules-v204-beta.md
* * Add multi-zone support for batch operations
* * Add support for multiple -d flags to specify multiple domains
* * Add -zf|--zones-file flag to load zones from a file
* * Add -y|--yes flag to skip confirmation prompts
* * Add zone deduplication to prevent processing same zone twice
* * Add confirmation prompt showing affected zones before execution
* * Add summary output with success/failure counts per zone
* New functions in cf-inc.sh:
* * _load_zones_file: Parse zones file with comment support
* * _deduplicate_zones: Remove duplicate zones from array
* * _confirm_zones: Display zones and prompt for confirmation
* * _run_on_zones: Execute command across multiple zones with progress
* Commands supporting multi-zone:
* * create-rules, update-rules, list-rules, delete-rules
* * get-settings, set-settings
* Files changed:
* * cloudflare-wordpress-rules.sh: Multi-zone CLI and command integration
* * cf-inc.sh: Multi-zone support functions
* * CHANGELOG.md: Release notes for v2.2.0
* * README.md: Multi-zone documentation and examples
* * VERSION: Bump to 2.2.0
* * TODO.md: Mark completed items
* * zones.txt.example: Template for zones file format
## Release 2.1.2
* (af39726) (HEAD -> dev, origin/dev) fix: add domain validation for get-settings and support filtering by specific setting parameter
* (2270998) Updated usage for get-settings and set-settings
## Release 2.1.1
* (de29bfb) (HEAD -> dev, origin/dev) chore: Updated README.md to better document .cloudflare file
* (f03c426) improvement: Updated authentication system.
* (68ac46b) Merged changes that were missing
* (32ed657) Added TODO.md
* (92b0b14) Small fixes
* (d5d41e5) Added mwp-rules-v204-beta.md
* (9e6d417) Added asn.txt for building rules
* (cf3f595) Updated API credentials system to enable multiple profiles
## Release 2.1.0
* (6dc4a1b) (HEAD -> dev, origin/dev) Small fixes
* (5f97c85) Created v204-beta rules
* (04727ce) Backup of default rules v203 and create v204 beta
* (1100cfc) improvement: Better messaging on what key/token is being utilized
* (23623ea) improvement: Renamed cloudflare-spc.sh to cloudflare-token.sh Added create-app-cf for app for cloudflare plugin Created list-perissions Created list-permission-groups
## Release 2.0.10
* improvement(spc): Improved test-token command
* fix(profiles): Fixed improper naming of profiles
* fix(bin): Fixed generate-md.sh locatiing profiles dir
## Release 2.0.9
* refactor: Brought in cf-inc-refactor.sh for reference
* enhance: Added ipblocks-ua template for rule R2
* fix: Renamed files
* improvement: Created ipblocks-ua-qs method
* fix: Updated .gitignore to only skip .json within profiles directory
* fix: Errors with tyepset and declare
* fix: Profiles with incorrect json
* improvement: Created print-profiles command
* feat(profile): Added block-event-calendar.json
* style: Added .shellcheckrc
* enhance: Added ips for blogvault and wp-umbrella, as well as useragents and querystrings for ipblocks-ua-qs
* refactor: Shifted old code into cf-inc-old.sh
* fix: Fixed shellcheck errors
* refactor: Fixed shellcheck errors in cf-in-api.sh increased to v1.5
* fix: Increase version number for cf-inc-api.sh properly.
* test: Added cf-settings.json
* fix: Changed WP Umbrella User Agent to WPUmbrella
* refactor: Moved settings based api commands to cf-inc-api.sh
* fix: Small adjustments
* refactor: Removed settings from cf-inc-old.sh
* refactor: Removed create-rules-v1
* refactor: Renamed create-rules-profile to create-rules
* refactor: Moved rules and profile functions to cf-inc-wp.sh
* Added some debugging
* Reverted shellcheck code.
* chore: Removed unecessary files and updated README.md
* docs: Updated cloudflare-waf-wordpress.md
* Small fixes
* feat: Created update-rule function
* Small changes
* fix(profile): Added profile data for rule_number and rule_version
* improvement: Added code for upgrading the default rule
* Added test-perms
* chore: Moved ipblocks-ua-qs to it's own folder.
* chore: Moving archives around
* improvement(rules): Updated default to include Infusionsoft useragent.
* fix: Moved generate-readme.sh to bin and updated paths
* chore: Moved scripts into /bin
* chore: Created default.md for default.json
## Release 2.0.8
* fix(core): Brought back set-settings
## Release 2.0.7
* fix(core): Merged code without testing.
## Release 2.0.6
* improvement(cf-api): Udpated cf-inc-api.sh to v1.4
* docs(cf-inc): Fixed documentation.
* refactor(cloudflare-spc): Refactored some aspects of cloudflare-spc
## Release 2.0.5
* improvement(inc): Updated cf-inc.sh
* improvement(core): Updated inc files formatting
* refactor(core): Moved api commands to cf-api-inc.sh
* improvement(api): Updated cf-inc-api.sh to v1.1
* improvement(api): Updated API file location
* improvement(api): Updated cfi-in-api.sh location
* improvement(api): Updated cf-inc-api.sh to 1.2
* improvement(core): Updated cf-inc.sh to 2.1
* improvement(cf-turnstile): Updated create command to handle multiple accounts
## Release 2.0.4
* improvement: Updated Managing WP rules to v201.
* fix: Fixed issue with MWP rules .md and json differing.
* improvement: Created profiles-archive of older profiles.
## Release 2.0.3
* refactor(spc): Refactored cloudflare-spc command
## Release 2.0.2
* improvement: Ask to delete all rules, versus one by one.
* improvement: Created profile with mwp-rules-v2 including event calendars bot blocking
* improvement: Created generate-readme.sh to generate/add CHANGELOG.md to README.md
## Release 2.0.1
* improvement(doc): Updated README.md
* improvement(profiles): Added mwp-rules-v1.json as an example
* fix: Addd /profiles to .gitignore for custom profile creation
## Release 2.0.0
* doc: Created CHANGELOG.md and command to generate it
* fix: Removed $ZONE_ID which is unused
* refactor: Moving cwr general commands into cf-inc.sh
* refactor: Clean-up and refactor to pass $ZONE_ID for functions
* fix: Adding pre-flight check.
* fix: Ensure user agents are contains not equals
* docs: Added more tests cf-create-filter.json cf-error.json cf-filter.json cf-rule.json cf-rules.json
* fix: Fixed deleting all rules
* test: Added more tests!
* refactor: Huge refactor for debugging
* refactor(major): Major refactor
## Release 1.2.0
* enhance: Creating cf-inc.sh and cf-api-inc.sh files
* enhance: Created cloudflare-turnstile.sh for turnstile widget creation
* improvement: Created tests directory with example cloudflare API json results
## Release 1.1.6
* fix(readme): Updated readme formartting
* fix(rulesv2): Added Let's Encrypt to useragent allow R2V2
## Release 1.1.5
* improvement(account-tokens): Added support for account owned tokens
* improvement(account-owned-tokens): Added additional permissions
* Added listing of account owned tokens.
* Updated README.md for cloudflare-spc.sh
## Release 1.1.4
* Updated user-agent for WP Umbrella to "WPUmbrella"
## Relase 1.1.3
* Updated firewall rules to v2, an overhaul of the rules.
* Using R1V2 for naming scheme, R1 = Rule 1, V2 = Version 2
## Release 1.1.2
* Small fix to allow for multiple zones.
## Release 1.1.1
* fix: Error message wasn't updated to use $CF_SPC_TOKEN
* fix: Updated Rule #4 to included woo password-strength-meter.min.js
## Release 1.1.0
* 5ca3b1b fix: Updated user agent for WP Umbrella
* 33d83dc refactor: Refactored cloudflare-spc.sh, watch out!
* 56fbd31 Updated
* b43d126 Cleaned up the code a bit, changed -t to allow for specifiying a token if nothing in env or .cloudflare file. Fixed error handling.
## Release 1.0.0
* ecb1bfa - Working create token command with zoneid (16 hours ago)
* 6b5a07e - Major overhaul of functions (17 hours ago) d5b64de - Small code refactor and renaming. (4 weeks ago)
* 6c5c384 Code refactoring and variable changes for Cloudflare token.
* 3a1f9c7 Removed git merge comments
* 668773d Updated permissions.
* 1199d75 Updated user agents
* 22ca705 Updated
* 9408e41 Merge branch 'main' into dev
* fbbd977 Updated
## Release 0.3.0
* f1b4dae * Added cloudflare-spc.sh
* * Created cloudflare-cache-wordpress.md for Cloudflare cache rules, and renamed cloudflare-protect-wordpress.md to cloudflare-waf-wordpress.md
* * Reworked the code to support profiles that are file based.
* 3ca859e Update cloudflare-protect-wordpress.md
* 2d54676 Updated README.md some more and added in -d and -dr options
* 022d174 Added symlink for cloudflare-wordpress-rules to cloudflare-wordpress-rules.sh
* 5ac8a8c Updated README.md with usage information.
* a959c74 Merge branch 'main' of github.com:managingwp/cloudflare-wordpress-rules into main
## Release 0.2.0
* aae599f Updated to add WP Umbrella User Agent
* 5a6d0c0 Merge branch 'main' of github.com:managingwp/cloudflare-wordpress-rules into main
* fc64011 Update README.md
* 84fc6a0 Update cloudflare-protect-wordpress.md
* 71b2a80 Success was read instead of green!
* 8f8d675 Improved code overall
## Release 0.1.0
* bc72ee3 Created cloudflare-wordpress-rules.sh as an example to create rules automatically.
* 6caf689 Update cloudflare-protect-wordpress.md
* 9fb62d5 Update cloudflare-protect-wordpress.md
* 1ce5e59 Update cloudflare-protect-wordpress.md
* 4804f60 Update and rename cloudflare-protect-wordpress.rules to cloudflare-protect-wordpress.md
* ca0b3e6 Create cloudflare-protect-wordpress.rules
* f3c5be1 Update README.md
* f920d51 Initial commit
