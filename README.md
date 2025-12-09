# Cloudflare WordPress Rules
This repository provides a bash script for the creation of Cloudflare WAF rules for WordPress specific sites. It also provides a script for creating API tokens and turnstile widgets for Cloudflare.
## Files
| File | Description |
| --- | --- |
| [cloudflare-waf-wordpress.md](cloudflare-waf-wordpress.md) | Contains all of the Cloudflare WAF expression rules that I've created. |
| [cloudflare-cache-wordpress.md](cloudflare-cache-wordpress.md) | Contains Cloudflare cache rules expressions. |
| [cloudflare-wordpress-rules.sh](cloudflare-wordpress-rules.sh) | Bash script to create Cloudflare WAF and Cache rules on a domain name through the Cloudflare API. Supports multi-zone operations. |
| [cloudflare-token.sh](cloudflare-token.sh) | Create and manage Cloudflare API tokens (including for the Super Page Cache plugin), with support for account-owned tokens. |
| [cloudflare-turnstile.sh](cloudflare-turnstile.sh) | Creates turnstile widgets for Cloudflare. |
| [zones.txt.example](zones.txt.example) | Example zones file for multi-zone operations. |

## Authentication (.cloudflare)
All scripts read credentials from a single config file at: `~/.cloudflare`.

You can define either generic (default) credentials or multiple named profiles. If multiple profiles exist, the scripts will offer an interactive menu to choose which profile to use.

### What you can define
- Generic (fallback) credentials:
  - `CF_ACCOUNT` + `CF_KEY` (Global API Key auth), or
  - `CF_TOKEN` (scoped API Token auth)
- Profile-based credentials (recommended):
  - `CF_ACCOUNT_<PROFILE>` + `CF_KEY_<PROFILE>`
  - `CF_TOKEN_<PROFILE>`

Profiles are any uppercase name you choose (e.g., `PROD`, `DEV`, `CLIENT1`). The scripts will detect all `CF_(ACCOUNT|TOKEN|KEY)_<PROFILE>` entries and list them for selection.

### Precedence (highest to lowest)
1. A specific profile you pass explicitly (future option)
2. Interactive choice (if multiple profiles are found)
3. Generic credentials: `CF_TOKEN` or `CF_ACCOUNT` + `CF_KEY`

### Examples
Minimal (generic) credentials:
```
# Uses a single default set for all scripts
CF_ACCOUNT=example@domain.com
CF_KEY=your_global_api_key
# OR
CF_TOKEN=your_api_token
```

Multiple profiles (recommended):
```
# Production
CF_ACCOUNT_PROD=prod@company.com
CF_KEY_PROD=prod_global_api_key
# OR
# CF_TOKEN_PROD=prod_api_token

# Development
CF_TOKEN_DEV=dev_api_token

# Client-specific
CF_ACCOUNT_CLIENT1=client1@theircompany.com
CF_TOKEN_CLIENT1=client1_api_token
```

Legacy (still supported):
```
# Super Page Cache (legacy keys remain compatible)
CF_ACCOUNT_SPC=spc@company.com
CF_TOKEN_SPC=spc_api_token

# Turnstile (legacy keys remain compatible)
CF_ACCOUNT_TS=turnstile@company.com
CF_TOKEN_TS=turnstile_api_token
```

See `.cloudflare.example` in the repo root for a complete, commented template.

### Notes
- Token auth is preferred: safer and easier to scope (`Zone.Firewall Services:Edit`, etc.).
- Some commands do not require authentication and will run without reading `~/.cloudflare`:
  - `list-profiles`
  - `print-profile <profile>`
  - `validate-profile <profile>`
  - `list-auth-profiles`

## [cloudflare-wordpress-rules.sh](cloudflare-wordpress-rules.sh)
Bash script to create and manage Cloudflare WAF rules for WordPress sites through the Cloudflare API. Supports batch operations across multiple zones.

### Usage
```
cloudflare-wordpress-rules -d <domain> -c <command> [options]

RULE COMMANDS
  create-rules <profile>          Create rules on domain using profile
  update-rules <profile>          Update rules on domain using profile
  upgrade-default-rules           Upgrade MWP default rules on domain
  list-rules                      List rules on domain
  delete-rule <id>                Delete specific rule by ID
  delete-rules                    Delete all rules on domain

PROFILE COMMANDS
  list-profiles                   List available rule profiles
  print-profile <profile>         Print rules from profile
  validate-profile <profile>      Validate profile JSON syntax

FILTER COMMANDS
  list-filters                    List filters on domain
  get-filter <id>                 Get specific filter by ID
  delete-filter <id>              Delete specific filter by ID
  delete-filters                  Delete all filters on domain

RULESET COMMANDS
  list-rulesets                   List rulesets on domain
  get-ruleset <id>                Get specific ruleset by ID
  get-ruleset-fw-custom           Get http_request_firewall_custom ruleset

SETTINGS COMMANDS
  get-settings                    Get security settings on domain
  set-settings <setting> <value>  Set security setting
    Settings: security_level, challenge_ttl, browser_integrity_check, always_use_https

AUTH COMMANDS
  list-auth-profiles              List available authentication profiles

OPTIONS
  -d, --domain <domain>         Domain to operate on (can be used multiple times)
  -zf, --zones-file <file>      Load zones from file (one per line)
  -y, --yes                     Skip confirmation prompt for multi-zone ops
  -c, --command <cmd>           Command to execute
  --debug                       Enable debug mode
  -dr, --dryrun                 Dry run, don't send to Cloudflare
```

### Examples
```bash
# Create rules on a single domain
cloudflare-wordpress-rules -d domain.com -c create-rules default

# List rules on a domain
cloudflare-wordpress-rules -d domain.com -c list-rules

# Delete a specific rule
cloudflare-wordpress-rules -d domain.com -c delete-rule 1234567890

# Get security settings
cloudflare-wordpress-rules -d domain.com -c get-settings

# Set security level
cloudflare-wordpress-rules -d domain.com -c set-settings security_level high
```

### Multi-Zone Operations (v2.2.0+)
The script supports running commands across multiple zones at once. This is useful for managing rules on many domains.

#### Specifying Multiple Domains
Use the `-d` flag multiple times:
```bash
cloudflare-wordpress-rules -d site1.com -d site2.com -d site3.com -c create-rules default
```

#### Using a Zones File
Create a text file with one domain or zone ID per line:
```bash
# zones.txt
site1.com
site2.com
site3.com
# Comments are supported
example.org  # inline comments too
```

Then reference it with `-zf`:
```bash
cloudflare-wordpress-rules -zf zones.txt -c create-rules default
```

You can also combine both methods:
```bash
cloudflare-wordpress-rules -zf zones.txt -d extra-site.com -c list-rules
```

#### Skip Confirmation
By default, the script will list all affected zones and ask for confirmation before proceeding. Use `-y` to skip:
```bash
cloudflare-wordpress-rules -zf zones.txt -c delete-rules -y
```

#### Commands Supporting Multi-Zone
- `create-rules` - Create rules on all specified zones
- `update-rules` - Update rules on all specified zones
- `list-rules` - List rules from all specified zones
- `delete-rules` - Delete rules from all specified zones
- `get-settings` - Get settings from all specified zones
- `set-settings` - Set settings on all specified zones

#### Output
The script will process each zone sequentially and provide a summary at the end showing:
- Total zones processed
- Number of successful operations
- Number of failed operations
- List of failed zones (if any)

### Profiles
Profiles are stored in the profiles directory. They are JSON files that contain the rules to be created. The profile name is the filename without the .json extension.

```
{
  "rules": [
    {
      "action": "block",
      "description": "Block bad bots",
      "filter": {
        "expression": "(http.user_agent contains \"WPScan\")",
        "paused": false
      }
    },
    {
      "action": "block",
      "description": "Block bad bots",
      "filter": {
        "expression": "(http.user_agent contains \"WPSpider\")",
        "paused": false
      }
    }
  ]
}
```

## [cloudflare-token.sh](cloudflare-token.sh)
This script creates and manages Cloudflare API tokens, including tokens for the Super Page Cache for Cloudflare WordPress plugin. Supports account-owned tokens.

### Usage
```
Usage: cloudflare-token.sh [command] [options]

Commands:
    create-token <domain> <token-name>    Create API token for domain
    list                                  List account tokens
    test-creds                            Test credentials against Cloudflare API
    test-token <token>                    Test created token against Cloudflare API

Options:
    -z, --zone <zoneid>           Set zone ID
    -a, --account <email>         Cloudflare account email address
    -t, --token <token>           API Token to use
    -ak, --apikey <apikey>        API Key to use
    -d, --debug                   Debug mode
    -dr, --dryrun                 Dry run mode
```

## [cloudflare-turnstile.sh](cloudflare-turnstile.sh)
This script creates and manages Cloudflare Turnstile widgets.

### Usage
```
Usage: cloudflare-turnstile.sh [command] [options]

Commands:
    create                                Create a turnstile widget
    list                                  List account turnstiles
    delete                                Delete a turnstile
    test-creds                            Test credentials against Cloudflare API

Options:
    -z, --zone <domain>             Zone domain name
    -a, --account <email>           Cloudflare account email address
    -t, --turnstile <sitekey>       Turnstile Sitekey
    -tn, --turnstile-name <name>    Turnstile Name
    -ak, --apikey <apikey>          API Key
    -d, --debug                     Debug mode
    -dr, --dryrun                   Dry run mode
```

# Changelog
Generated using `git log --pretty=format:"## %s%n%b%n" | sed '/^## /b; /^[[:space:]]*$/b; s/^/* /' > CHANGELOG.md`
<!--- CHANGELOG --->
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
<!--- END CHANGELOG --->
