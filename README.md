# Cloudflare WordPress Rules
This repository holds common Cloudflare WordPress Rules.

# [cloudflare-protect-wordpress.md](cloudflare-protect-wordpress.md)
Contains all of the Cloudflare WAF expression rules that I've created.

# [cloudflare-wordpress-rules.sh](cloudflare-wordpress-rules.sh)
Bash script to create Cloudflare WAF rules on a domain name through the Cloudflare API.
## Usage
```
cloudflare-wordpress-rules <domain.com> <cmd> <id>

Commands
   create-rules <profile>     - Create rules on domain
   get-rules                  - Get rules
   delete-rule                - Delete rule
   delete-filter <id>         - Delete rule ID on domain
   get-filters                - Get Filters
   get-filter-id <id>         - Get Filter <id>

Profiles - *Not functional yet*
   protect-wp                 - The 5 golden rules, see https://github.com/managingwp/cloudflare-wordpress-rules

Examples
   cloudflare-wordpress-rules testdomain.com delete-filter 32341983412384bv213v
   cloudflare-wordpress-rules testdomian.com create-rules

Cloudflare API Credentials should be placed in $HOME/.cloudflare
```
