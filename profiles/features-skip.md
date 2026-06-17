# Skip Action

The **Skip** action replaces the deprecated **Allow** and **Bypass** actions from the Firewall Rules API.

With the Skip action you can:
- Stop running all the remaining custom rules (equivalent to the old `Allow`)
- Avoid running other security products (equivalent to the old `Bypass`)
- A combination of the above

## Configuration

The Skip action is configured via `action_parameters` in a v3 profile:

### Skip all remaining custom rules

```json
{
  "description": "R1V300 - Skip remaining custom rules for trusted IPs",
  "expression": "(ip.src in { 192.0.2.1 })",
  "action": "skip",
  "enabled": true,
  "logging": { "enabled": false },
  "action_parameters": {
    "ruleset": "current"
  }
}
```

- `"ruleset": "current"` — Skip all remaining custom rules in the current ruleset
- Logging is typically disabled for skip rules to avoid noise on legitimate traffic

### Skip specific security products

```json
{
  "description": "R2V300 - Skip WAF managed rules and rate limiting for API",
  "expression": "(http.request.uri.path contains \"/api/\")",
  "action": "skip",
  "enabled": true,
  "logging": { "enabled": false },
  "action_parameters": {
    "phases": [
      "http_request_firewall_managed",
      "http_ratelimit"
    ]
  }
}
```

Valid phase names for `phases`:
- `http_request_firewall_managed` — Skip WAF Managed Rules
- `http_ratelimit` — Skip Rate Limiting rules
- `http_request_firewall_custom` — Skip other custom rules
- `http_request_sbfm` — Skip Security Bad Flood (formerly)
- `ddos_l7` — Skip L7 DDoS rules

### Skip both remaining rules AND security products

```json
{
  "description": "R1V300 - Allow trusted bots through all security",
  "expression": "(cf.client.bot)",
  "action": "skip",
  "enabled": true,
  "logging": { "enabled": false },
  "action_parameters": {
    "ruleset": "current",
    "phases": [
      "http_request_firewall_managed",
      "http_ratelimit"
    ]
  }
}
```

## Builder Functions

The following helper functions are available for programmatic use:

```bash
# Skip all remaining custom rules
cf_ruleset_build_rule_payload_skip "desc" "expr" "current"

# Skip specific security products
cf_ruleset_build_rule_payload_skip "desc" "expr" "" "http_ratelimit"

# Both
cf_ruleset_build_rule_payload_skip "desc" "expr" "current" "http_ratelimit" "http_request_firewall_managed"
```

## Migration Notes

| Old Action | New Action | Migration |
|---|---|---|
| `allow` | `skip` with `"ruleset": "current"` | Direct replacement |
| `bypass` | `skip` with `"phases": [...]` | Specify which products to skip |
| `allow` + `bypass` combo | `skip` with both `ruleset` and `phases` | Combine into one rule |
