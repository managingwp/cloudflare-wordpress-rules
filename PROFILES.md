# Profile Format Reference

This document describes the profile JSON format used by `cloudflare-wordpress-rules.sh` to define WAF rules.

## Schema Versions

| Version | Description | Status |
|---|---|---|
| v2 | Legacy format using `priority` field with `allow`/`bypass` actions for the deprecated Firewall Rules API | Deprecated |
| v3 | Rulesets API format with `enabled`, `logging`, and `action_parameters` fields | **Current** |

## v3 Profile Format

The v3 format maps directly to the Cloudflare Rulesets API. Rule ordering is determined by **array position** — rules are evaluated in order.

### Top-Level Structure

```json
{
  "name": "my-profile",
  "description": "My WordPress WAF rules",
  "version": 3,
  "profiles_version": "3.0.0",
  "phase": "http_request_firewall_custom",
  "rules": [...]
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | Yes | Profile name (used for identification) |
| `description` | string | Yes | Human-readable description |
| `version` | number | Yes | Schema version — must be `3` |
| `profiles_version` | string | No | Version of this profile file |
| `phase` | string | No | Ruleset phase (default: `http_request_firewall_custom`) |
| `rules` | array | Yes | Array of rule objects |

### Rule Object

```json
{
  "rule_number": "1",
  "rule_version": "300",
  "description": "R1V300 - Allow trusted IPs",
  "expression": "(ip.src in { 192.0.2.1 192.0.2.2 })",
  "action": "skip",
  "enabled": true,
  "logging": { "enabled": false },
  "action_parameters": {
    "ruleset": "current"
  }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `rule_number` | string | Yes | Internal rule identifier for upgrade tracking |
| `rule_version` | string | Yes | Internal version for upgrade comparison |
| `description` | string | Yes | Human-readable description |
| `expression` | string | Yes | Cloudflare WAF expression |
| `action` | string | Yes | Action to take when rule matches |
| `enabled` | boolean | No | Whether the rule is active (default: `true`) |
| `logging` | object | No | Logging configuration (default: `{"enabled": true}`) |
| `action_parameters` | object | No | Action-specific parameters |

### Supported Actions

| Action | Description | v2 Equivalent |
|---|---|---|
| `block` | Block the request | `block` |
| `challenge` | Issue a CAPTCHA challenge | `challenge` |
| `js_challenge` | Issue a JavaScript challenge | `js_challenge` |
| `managed_challenge` | Issue a managed challenge (CAPTCHA or JS based on risk) | `managed_challenge` |
| `log` | Log the request without taking action | `log` |
| `skip` | Skip remaining rules and/or security products | `allow` + `bypass` |
| `execute` | Execute another ruleset | — |

### Skip Action Configuration

The `skip` action replaces the deprecated `allow` and `bypass` actions.

**Skip remaining custom rules:**
```json
"action_parameters": {
  "ruleset": "current"
}
```

**Skip specific security products:**
```json
"action_parameters": {
  "phases": ["http_request_firewall_managed", "http_ratelimit"]
}
```

**Both:**
```json
"action_parameters": {
  "ruleset": "current",
  "phases": ["http_request_firewall_managed"]
}
```

### Custom Block Response

The `block` action supports a custom response configuration:

```json
"action_parameters": {
  "response": {
    "status_code": 403,
    "content": "Your request was blocked.",
    "content_type": "text/plain"
  }
}
```

Supported `content_type` values: `text/html`, `text/plain`, `application/json`, `application/xml`, `text/xml`.

### Rate Limiting Configuration

Rate limiting can be applied to any action:

```json
"action_parameters": {
  "ratelimit": {
    "characteristics": ["ip.src"],
    "period": 60,
    "requests_per_period": 100,
    "mitigation_timeout": 300
  }
}
```

### Converting v2 to v3

Use the conversion script:
```bash
bin/convert-profile-v2-to-v3.sh profiles/default.json profiles/default-v3.json
```

Key conversions:
- `priority` → removed (order is array position)
- `allow` → `skip` with `"action_parameters": { "ruleset": "current" }`
- `bypass` → `skip` with `"action_parameters": { "phases": [...] }`
- `enabled: true` is added to each rule
- `logging` is added (disabled for skip rules to reduce noise)

### Validation

Validate a profile against the Rulesets API schema:
```bash
cloudflare-wordpress-rules -c validate-profile <profile-name>
```
