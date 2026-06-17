# Rate Limiting

The Rulesets API supports rate limiting configuration within custom rules. This allows you to define rate limits as part of your WAF custom rules rather than using a separate Rate Limiting ruleset.

> **Note**: Rate limiting in custom rules is available in certain Cloudflare plans. Check your plan's eligibility before using this feature.

## Configuration

Rate limiting is configured via `action_parameters.ratelimit` in a v3 profile:

### Basic rate limit — IP-based

```json
{
  "description": "R5V300 - Rate limit: 100 requests per 60 seconds per IP",
  "expression": "(http.request.uri.path contains \"/wp-login.php\")",
  "action": "block",
  "enabled": true,
  "logging": { "enabled": true },
  "action_parameters": {
    "ratelimit": {
      "characteristics": ["ip.src"],
      "period": 60,
      "requests_per_period": 100,
      "mitigation_timeout": 300
    }
  }
}
```

### Rate limit with counting expression

```json
{
  "description": "R6V300 - Rate limit login attempts",
  "expression": "(http.request.uri.path eq \"/wp-login.php\")",
  "action": "block",
  "enabled": true,
  "logging": { "enabled": true },
  "action_parameters": {
    "ratelimit": {
      "characteristics": ["ip.src"],
      "period": 120,
      "requests_per_period": 20,
      "mitigation_timeout": 600,
      "counting_expression": "(http.request.method eq \"POST\")"
    }
  }
}
```

### Advanced rate limit — multiple characteristics

```json
{
  "description": "R7V300 - Rate limit per IP + country",
  "expression": "(http.request.uri.path contains \"/api/\")",
  "action": "managed_challenge",
  "enabled": true,
  "logging": { "enabled": true },
  "action_parameters": {
    "ratelimit": {
      "characteristics": ["ip.src", "ip.geoip.country"],
      "period": 60,
      "requests_per_period": 50,
      "mitigation_timeout": 120,
      "requests_to_origin": true
    }
  }
}
```

## Rate Limit Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `characteristics` | array of string | **Yes** | Request characteristics for rate limiting (e.g., `["ip.src"]`, `["cf.unique_id"]`) |
| `period` | number | **Yes** | Period in seconds over which the counter is incremented |
| `requests_per_period` | number | No | Threshold of requests per period before action is triggered |
| `mitigation_timeout` | number | No | Time in seconds after which the action is disabled following first execution |
| `counting_expression` | string | No | Expression defining when the rate limit counter should be incremented (defaults to rule expression) |
| `score_per_period` | number | No | Score threshold per period for triggering the action |
| `score_response_header_name` | string | No | Response header name from origin containing the score |
| `requests_to_origin` | boolean | No | Only count requests that reach the origin |

## Builder Function

```bash
# Basic: 100 requests per 60 seconds per IP
cf_ruleset_build_rule_payload_ratelimit \
  "desc" "expr" \
  '["ip.src"]' 60 100 300

# With counting expression
cf_ruleset_build_rule_payload_ratelimit \
  "desc" "expr" \
  '["ip.src"]' 120 20 600
```

## Important Notes

- Rate limiting in custom rules counts requests based on the `characteristics` you define
- The `action` field determines what happens when the rate limit is exceeded (block, challenge, etc.)
- `mitigation_timeout` is the cooldown period after the action triggers
- Not all plans support rate limiting in custom rules — check your Cloudflare plan
