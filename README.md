# Cloudflare WordPress Rules
This repository holds common Cloudflare WordPress Rules and supporting scripts.

## [cloudflare-waf-wordpress.md](cloudflare-waf-wordpress.md)
* Contains all of the Cloudflare WAF expression rules that I've created.
* It's regularly updated.
* You can copy and paste the contents into the Cloudflare expression builder.
* Previous Version History

## [cloudflare-cache-wordpress.md](cloudflare-cache-wordpress.md)
* Contains Cloudflare cache rules expressions.

# Scripts
## [cloudflare-wordpress-rules.sh](cloudflare-wordpress-rules.sh)
* Bash script to create Cloudflare WAF and Cache rules on a domain name through the Cloudflare API.
* In beta, so use at your own risk.

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

Version: 0.0.1
```
## [cloudflare-wordpress-spc.sh](cloudflare-wordpress-spc.sh)
This script creates an API token with the appropriate permissions that works with the Super Page Cache for Cloudflare WordPress plugin.
### Usage
```
Usage: ./cloudflare-spc.sh create <zone/domainname> <token-name> | list
	Creates appropriate api token and permissions for the Super Page Cache for Cloudflare WordPress plugin.

	create <zone> <token-name>         - Creates a token called <token name> for <zone>
    list                               - Lists account tokens.

Environment variables:
    CF_ACCOUNT  -  email address (as -E option)
    CF_TOKEN    -  API token (as -T option)

Configuration file for credentials:
    Create a file in \$HOME/.cloudflare with both CF_ACCOUNT and CF_TOKEN defined.

    CF_ACCOUNT=example@example.com
    CF_TOKEN=<token>
```

# Configuration
Place your Cloudflare API token in a file called `.cloudflare` in your home directory.

```
CF_ACCOUNT=""
CF_TOKEN=""
```

If you want to use a Cloudflare API key you can use CF_KEY instead of CF_TOKEN.

# Todo
* Add more rules
* Test key/token and return permissions.

# FAQ

## Run on multiple domains
You can run the script on multiple domains by adding the domain names to the command line.

```
# Shell script to set multiple settings for one domain
for domain in domain1.com domain2.com domain3.com
do
    cloudflare-wordpress-rules.sh set-settings $domain challenge_ttl 86400
done
```
# Rules to Ruleset Change
```
curl https://api.cloudflare.com/client/v4/zones/{zone_id}/rulesets/{ruleset_id}/rules \
--header "Authorization: Bearer <API_TOKEN>" \
--header "Content-Type: application/json" \
--data '{
  "description": "My custom rule",
  "expression": "(ip.geoip.country eq \"GB\" or ip.geoip.country eq \"FR\") and cf.threat_score > 10",
  "action": "challenge"
}'
```

# Change Log