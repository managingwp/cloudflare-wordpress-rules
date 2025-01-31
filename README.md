# Cloudflare WordPress Rules
This repository holds common Cloudflare WordPress Rules and supporting scripts.

# Cloudflare WAF Rules

## [cloudflare-waf-wordpress.md](cloudflare-waf-wordpress.md)
* Contains all of the Cloudflare WAF expression rules that I've created.
* It's regularly updated.
* You can copy and paste the contents into the Cloudflare expression builder.

## [cloudflare-cache-wordpress.md](cloudflare-cache-wordpress.md)
* Contains Cloudflare cache rules expressions.

# Scripts
## [cloudflare-wordpress-rules.sh](cloudflare-wordpress-rules.sh)
* Bash script to create Cloudflare WAF and Cache rules on a domain name through the Cloudflare API.
* It has support for profiles, but they are not yet functional.
### Usage
```
Usage: cloudflare-wordpress-rules (-d|-dr) <domain.com> <command>

Options
   -d                         - Debug mode
   -dr                        - Dry run, don't send to Cloudflare

Commands
   create-rules <profile>     - Create rules on domain
   create-cache-rules         - Not implemented yet, coming soon.
   get-rules                  - Get rules
   delete-rule                - Delete rule
   delete-filter <id>         - Delete rule ID on domain
   get-filters                - Get Filters
   get-filter-id <id>         - Get Filter <id>

Profiles - * Not yet functional*
   protect-wp                 - The 5 golden rules, see https://github.com/managingwp/cloudflare-wordpress-rules

Examples
   cloudflare-wordpress-rules testdomain.com delete-filter 32341983412384bv213v
   cloudflare-wordpress-rules testdomian.com create-rules

Environment variables:
    CF_ACCOUNT  -  email address (as -E option)
    CF_TOKEN    -  API token (as -T option)

Configuration file for credentials:
    Create a file in \$HOME/.cloudflare with both CF_ACCOUNT and CF_TOKEN defined.

    CF_ACCOUNT=example@example.com
    CF_TOKEN=<token>
```

## [cloudflare-spc.sh](cloudflare-spc.sh)
* This script creates an API token with the appropriate permissions that works with the Super Page Cache for Cloudflare WordPress plugin. It has support for account owned tokens.

### Usage
```
Usage: ./cloudflare-spc.sh [create <zone> <token-name> | list]

Creates appropriate api token and permissions for the Super Page Cache for Cloudflare WordPress plugin.

Commands:
    create-token <domain-name> <token-name> (-z|-a|-t|-ak)           - Creates a token called <token name> for <zone>, if <token-name> blank then (zone)-spc used
    list -t [token] | -a [account] -ak [api-key]                     - Lists account tokens.
    test-creds -t [token] | -a [account] -ak [api-key]               - Test credentials against Cloudflare API.
    test-token <token>                                               - Test created token against Cloudflare API.

Options:
    -z|--zone [zoneid]                - Set zoneid
    -a|--account [name@email.com]     - Cloudflare account email address
    -t|--token [token]                - API Token to use for creating the new token.
    -ak|--apikey [apikey]             - API Key to use for creating the new token.
    -d|--debug                        - Debug mode
    -dr|--dryrun                      - Dry run mode

Environment variables:
    CF_SPC_ACCOUNT      - Cloudflare account email address
    CF_SPC_KEY          - Cloudflare Global API Key
    CF_SPC_TOKEN        - Cloudflare API token.

Configuration file for credentials:
    Create a file in $HOME/.cloudflare with both CF_SPC_ACCOUNT and CF_SPC_KEY defined or CF_SPC_TOKEN. Only use a KEY or Token, not both.

    CF_SPC_ACCOUNT=example@example.com
    CF_SPC_KEY=<global api key>
```

## [cloudflare-turnstile.sh](cloudflare-turnstile.sh)
* This script creates an a turnstile widget for Cloudflare.
### Usage
```
Usage: ./cloudflare-turnstile.sh [create <zone> <name> | list]

Creates appropriate Cloudflare turnstile api id and key.

Commands:
    create -z <domain-name> -tn <turnstile-name> (-z|-a|-t|-ak)                  - Creates a turnstile called <turnstile name> for <zone>, if <turnstile-name> blank then (zone)-spc used
    list -t [turnstile sitekey] | -z [domain name] | -a [accountemail]           - Lists account turnstiles.
    delete -t [turnstile sitekey] | -z [domain name] | -a [accountemail]         - Deletes a turnstile.
    test-creds -t [turnstile sitekey] | -a [account] -ak [api-key]               - Test credentials against Cloudflare API.

Options:
    -z|--zone [domain name]                - Zone domain name
    -a|--account [name@email.com]          - Cloudflare account email address
    -t|--turnstile [turnstile sitekey]     - Turnstile Sitekey
    -tn|--turnstile-name [name]            - Turnstile Name
    -ak|--apikey [apikey]                  - API Key to use for creating the new turnstile.
    -d|--debug                             - Debug mode
    -dr|--dryrun                           - Dry run mode

Environment variables:
    CF_TS_ACCOUNT      - Cloudflare account email address
    CF_TS_KEY          - Cloudflare Global API Key
    CF_TS_TOKEN        - Cloudflare API token.

Configuration file for credentials:
    Create a file in $HOME/.cloudflare with both CF_TS_ACCOUNT and CF_TS_KEY defined or CF_TS_TOKEN. Only use a KEY or Token, not both.

    CF_TS_ACCOUNT=example@example.com
    CF_TS_KEY=<global api key>    

```

## Release 2.0.0
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