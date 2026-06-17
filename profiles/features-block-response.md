# Custom Block Responses

The **Block** action in the Rulesets API supports customizing the response returned to blocked requests. This was not available in the deprecated Firewall Rules API.

## Configuration

The custom response is configured via `action_parameters.response` in a v3 profile:

### Basic custom block response

```json
{
  "description": "R2V300 - Block with custom plain text response",
  "expression": "(http.request.uri.path eq \"/xmlrpc.php\")",
  "action": "block",
  "enabled": true,
  "logging": { "enabled": true },
  "action_parameters": {
    "response": {
      "status_code": 403,
      "content": "Your request was blocked by Cloudflare WordPress Rules.",
      "content_type": "text/plain"
    }
  }
}
```

### HTML response

```json
{
  "description": "R2V300 - Block with custom HTML response",
  "expression": "(ip.geoip.country in {\"XX\"})",
  "action": "block",
  "enabled": true,
  "logging": { "enabled": true },
  "action_parameters": {
    "response": {
      "status_code": 403,
      "content": "<!DOCTYPE html><html><head><title>Blocked</title></head><body><h1>Access Denied</h1><p>Your request has been blocked.</p></body></html>",
      "content_type": "text/html"
    }
  }
}
```

### JSON response

```json
{
  "description": "R2V300 - Block with custom JSON response",
  "expression": "(http.request.uri.path eq \"/wp-json/api/\")",
  "action": "block",
  "enabled": true,
  "logging": { "enabled": true },
  "action_parameters": {
    "response": {
      "status_code": 403,
      "content": "{\"error\":\"blocked\",\"message\":\"Access denied\",\"code\":403}",
      "content_type": "application/json"
    }
  }
}
```

### XML response

```json
{
  "action_parameters": {
    "response": {
      "status_code": 403,
      "content": "<?xml version=\"1.0\" encoding=\"UTF-8\"?><error><message>Blocked</message></error>",
      "content_type": "application/xml"
    }
  }
}
```

## Response Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `status_code` | number | `403` | HTTP status code to return |
| `content` | string | Cloudflare default | The response body |
| `content_type` | string | `text/html` | MIME type of the response |

Supported `content_type` values:
- `text/html`
- `text/plain`
- `application/json`
- `application/xml`
- `text/xml`

## Builder Function

```bash
# Default (403, plain text)
cf_ruleset_build_rule_payload_block "desc" "expr"

# Custom status and JSON response
cf_ruleset_build_rule_payload_block "desc" "expr" 429 '{"error":"rate_limited"}' "application/json"
```

## Migration Notes

- The old Firewall Rules API returned a default Cloudflare 1020 error page for blocked requests
- The new Rulesets API allows full customization of the block response
- You can set a zone-wide default WAF block page in **Error Pages > WAF block** in the dashboard
- Per-rule custom responses (via `action_parameters`) override the zone-wide default
