# Cloudflare WordPress Rules
This repository holds common Cloudflare WordPress Rules.

# [cloudflare-protect-wordpress.md](cloudflare-protect-wordpress.md)
* Contains all of the Cloudflare WAF expression rules that I've created.
* It's regularly updated.
* You can copy and paste the contents into the Cloudflare expression builder.


# [cloudflare-wordpress-rules.sh](cloudflare-wordpress-rules.sh)
* Bash script to create Cloudflare WAF rules on a domain name through the Cloudflare API.
* In beta, so use at your own risk.

## Usage
```
Usage: cloudflare-wordpress-rules (-d|-dr) <domain.com> <command>

Options
   -d                         - Debug mode
   -dr                        - Dry run, don't send to Cloudflare

Commands
   create-rules <profile>     - Create rules on domain
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

Cloudflare API Credentials should be placed in $HOME/.cloudflare

Version: 0.0.1
```
