---
title: Deploy a custom ruleset
description: Learn how to deploy a custom ruleset to your Cloudflare account.
image: https://developers.cloudflare.com/core-services-preview.png
---

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/ruleset-engine/llms.txt  
> Use this file to discover all available pages before exploring further.

[Skip to content](#%5Ftop) 

# Deploy a custom ruleset

To deploy a custom ruleset, add a rule with `execute` action to the list of rules of a phase [entry point ruleset](https://developers.cloudflare.com/ruleset-engine/about/rulesets/#entry-point-ruleset) at the account or zone level. The expression of the new rule will define when the custom ruleset will run.

You can only deploy custom rulesets in an entry point ruleset with the same scope. For example, a custom ruleset defined at the account level can only be deployed at the account level.

If you are using Terraform, refer to [WAF custom rules configuration using Terraform](https://developers.cloudflare.com/terraform/additional-configurations/waf-custom-rules/#create-and-deploy-a-custom-ruleset) for examples of creating and deploying custom rulesets.

If you are using the Cloudflare dashboard, refer to [Work with custom rulesets in the dashboard](https://developers.cloudflare.com/waf/account/custom-rulesets/create-dashboard/).

Note

Currently, zone-level custom rulesets are only available in the [http\_request\_firewall\_custom](https://developers.cloudflare.com/waf/custom-rules/custom-rulesets/#deploy-a-custom-ruleset-via-api) phase.

## Before you begin

1. Obtain the name of the [phase](https://developers.cloudflare.com/ruleset-engine/reference/phases-list/) where you want to deploy the custom ruleset.
2. [Create a custom ruleset](https://developers.cloudflare.com/ruleset-engine/custom-rulesets/create-custom-ruleset/) and keep the ID of the new custom ruleset.
3. [Fetch the rules already present in the phase entry point ruleset](https://developers.cloudflare.com/ruleset-engine/basic-operations/view-rulesets/#view-the-rules-included-in-a-ruleset). You must include in the `PUT` request all existing rules you want to keep.

## Example A - Account-level deployment

The following `PUT` request adds a rule that executes a custom ruleset when the zone name matches `example.com`.

In the `PUT` request, you must include the IDs of all existing rules you want to keep. The response will include all the rules in the phase entry point ruleset after the update.

Required API token permissions

At least one of the following [token permissions](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)is required:
* `Mass URL Redirects Write`
* `Magic Firewall Write`
* `L4 DDoS Managed Ruleset Write`
* `Transform Rules Write`
* `Select Configuration Write`
* `Account WAF Write`
* `Account Rulesets Write`
* `Logs Write`

Update an account entry point ruleset

```

curl "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/rulesets/phases/http_request_firewall_custom/entrypoint" \

  --request PUT \

  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \

  --json '{

    "rules": [

        {

            "action": "execute",

            "description": "Execute custom ruleset",

            "expression": "(cf.zone.name == \"example.com\") and cf.zone.plan eq \"ENT\"",

            "action_parameters": {

                "id": "<CUSTOM_RULESET_ID>"

            }

        },

        {

            "id": "<EXISTING_PHASE_RULE_ID_1>"

        },

        {

            "id": "<EXISTING_PHASE_RULE_ID_2>"

        }

    ]

  }'


```

```

{

  "result": {

    "id": "<ACCOUNT_PHASE_RULESET_ID>",

    "name": "http_request_firewall_custom phase entry point ruleset for my account",

    "description": "Execute several rulesets",

    "kind": "root",

    "version": "3",

    "rules": [

      {

        "id": "<PHASE_RULE_ID>",

        "version": "1",

        "action": "execute",

        "description": "Execute custom ruleset",

        "action_parameters": {

          "id": "<CUSTOM_RULESET_ID>",

          "version": "latest"

        },

        "expression": "(cf.zone.name == \"example.com\") and cf.zone.plan eq \"ENT\"",

        "last_updated": "2021-03-18T18:35:14.135697Z",

        "ref": "<PHASE_RULE_REF>",

        "enabled": true

      },

      {

        "id": "<EXISTING_PHASE_RULE_ID_1>",

        "version": "1",

        "action": "execute",

        "action_parameters": {

          "id": "<EXECUTED_RULESET_ID_1>",

          "version": "latest"

        },

        "expression": "(cf.zone.name eq \"example.com\") and cf.zone.plan eq \"ENT\"",

        "last_updated": "2021-03-16T15:51:49.180378Z",

        "ref": "<EXISTING_PHASE_RULE_REF_1>",

        "enabled": true

      },

      {

        "id": "<EXISTING_PHASE_RULE_ID_2>",

        "version": "1",

        "action": "execute",

        "action_parameters": {

          "id": "<EXECUTED_RULESET_ID_2>",

          "version": "latest"

        },

        "expression": "(cf.zone.name eq \"example.com\") and cf.zone.plan eq \"ENT\"",

        "last_updated": "2021-03-16T15:50:29.861157Z",

        "ref": "<EXISTING_PHASE_RULE_REF_2>",

        "enabled": true

      }

    ],

    "last_updated": "2021-03-18T18:35:14.135697Z",

    "phase": "http_request_firewall_custom"

  },

  "success": true,

  "errors": [],

  "messages": []

}


```

Warning

When deploying the custom ruleset at the account level, you must use parentheses to enclose any custom conditions and end your expression with `and cf.zone.plan eq "ENT"` like in the example above, or else the API operation will fail.

## Example B - Zone-level deployment

The following `PUT` request adds a rule to a zone-level entry point ruleset that executes a custom ruleset with ID `"<CUSTOM_RULESET_ID>"` for requests targeting the `/login` URI path.

You must include in the `PUT` request the IDs of all existing rules you want to keep. The response will include all the rules in the phase entry point ruleset after the update.

Required API token permissions

At least one of the following [token permissions](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)is required:
* `Response Compression Write`
* `Config Settings Write`
* `Dynamic URL Redirects Write`
* `Cache Settings Write`
* `Custom Errors Write`
* `Origin Write`
* `Managed headers Write`
* `Zone Transform Rules Write`
* `Mass URL Redirects Write`
* `Magic Firewall Write`
* `L4 DDoS Managed Ruleset Write`
* `HTTP DDoS Managed Ruleset Write`
* `Sanitize Write`
* `Transform Rules Write`
* `Select Configuration Write`
* `Bot Management Write`
* `Zone WAF Write`
* `Account WAF Write`
* `Account Rulesets Write`
* `Logs Write`
* `Logs Write`

Update a zone entry point ruleset

```

curl "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/phases/http_request_firewall_custom/entrypoint" \

  --request PUT \

  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \

  --json '{

    "rules": [

        {

            "action": "execute",

            "description": "Execute custom ruleset (zone)",

            "expression": "(http.request.uri.path eq \"/login\")",

            "action_parameters": {

                "id": "<CUSTOM_RULESET_ID>"

            }

        },

        {

            "id": "<EXISTING_PHASE_RULE_ID_1>"

        }

    ]

  }'


```

```

{

  "result": {

    "id": "<ZONE_PHASE_RULESET_ID>",

    "name": "http_request_firewall_custom phase entry point ruleset for my zone",

    "description": "",

    "kind": "zone",

    "version": "3",

    "rules": [

      {

        "id": "<PHASE_RULE_ID>",

        "version": "1",

        "action": "execute",

        "description": "Execute custom ruleset (zone)",

        "action_parameters": {

          "id": "<CUSTOM_RULESET_ID>",

          "version": "latest"

        },

        "expression": "(http.request.uri.path eq \"/login\")",

        "last_updated": "2025-08-18T18:35:14.135697Z",

        "ref": "<PHASE_RULE_REF>",

        "enabled": true

      },

      {

        "id": "<EXISTING_PHASE_RULE_ID_1>",

        "version": "1",

        "action": "managed_challenge",

        "expression": "(cf.waf.score lt 20 and http.request.uri.path wildcard \"/admin/*\")",

        "last_updated": "2025-08-16T15:51:49.180378Z",

        "ref": "<EXISTING_PHASE_RULE_REF_1>",

        "enabled": true

      }

    ],

    "last_updated": "2025-08-18T18:35:14.135697Z",

    "phase": "http_request_firewall_custom"

  },

  "success": true,

  "errors": [],

  "messages": []

}


```

Note

Currently, zone-level custom rulesets are only available in the [http\_request\_firewall\_custom](https://developers.cloudflare.com/waf/custom-rules/custom-rulesets/#deploy-a-custom-ruleset-via-api) phase.

```json
{"@context":"https://schema.org","@type":"BreadcrumbList","itemListElement":[{"@type":"ListItem","position":1,"item":{"@id":"/directory/","name":"Directory"}},{"@type":"ListItem","position":2,"item":{"@id":"/ruleset-engine/","name":"Ruleset Engine"}},{"@type":"ListItem","position":3,"item":{"@id":"/ruleset-engine/custom-rulesets/","name":"Work with custom rulesets"}},{"@type":"ListItem","position":4,"item":{"@id":"/ruleset-engine/custom-rulesets/deploy-custom-ruleset/","name":"Deploy a custom ruleset"}}]}
```
