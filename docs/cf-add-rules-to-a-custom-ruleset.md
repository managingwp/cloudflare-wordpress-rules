---
title: Add rules to a custom ruleset
description: Add rules to an existing custom ruleset using the API.
image: https://developers.cloudflare.com/core-services-preview.png
---

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/ruleset-engine/llms.txt  
> Use this file to discover all available pages before exploring further.

[Skip to content](#%5Ftop) 

# Add rules to a custom ruleset

To add rules to an existing custom ruleset, use the [Update an account or zone ruleset](https://developers.cloudflare.com/api/resources/rulesets/methods/update/) operation and pass the rules in an array. Each rule has an expression and an action.

Choose the appropriate API method

The [Update an account or zone ruleset](https://developers.cloudflare.com/api/resources/rulesets/methods/update/) operation replaces all the rules in the ruleset with the rules in the request. Use this API operation when you need to add or update several rules at once. This operation updates the ruleset version number only once.

Depending on the update you want to perform, consider using one of the following API operations instead:

* Add a single rule to an existing custom ruleset: Use the [Create an account or zone ruleset rule](https://developers.cloudflare.com/api/resources/rulesets/subresources/rules/methods/create/) operation. Refer to [Add a rule to a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/add-rule/) for an example.
* Update a single rule in a custom ruleset: Use the [Update an account or zone ruleset rule](https://developers.cloudflare.com/api/resources/rulesets/subresources/rules/methods/edit/) operation. Refer to [Update a rule in a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/update-rule/) for an example.

If you are using Terraform, refer to [WAF custom rules configuration using Terraform](https://developers.cloudflare.com/terraform/additional-configurations/waf-custom-rules/#create-and-deploy-a-custom-ruleset) for examples of creating and deploying custom rulesets.

If you are using the Cloudflare dashboard, refer to [Work with custom rulesets in the dashboard](https://developers.cloudflare.com/waf/account/custom-rulesets/create-dashboard/).

## Add rules

The following request adds two rules to a custom ruleset at the account level with ID `$RULESET_ID`. These will be the only two rules in the ruleset.

The response will include the rule ID of the new rules in the `id` field.

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

Update an account ruleset

```

curl "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/rulesets/$RULESET_ID" \

  --request PUT \

  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \

  --json '{

    "rules": [

        {

            "expression": "(ip.src.country in {\"GB\" \"FR\"} and cf.bot_management.score < 20 and not cf.bot_management.verified_bot)",

            "action": "challenge",

            "description": "challenge GB and FR based on bot score"

        },

        {

            "expression": "not http.request.uri.path matches \"^/api/.*$\"",

            "action": "challenge",

            "description": "challenge not /api"

        }

    ]

  }'


```

```

{

  "result": {

    "id": "<CUSTOM_RULESET_ID>",

    "name": "Custom Ruleset 1",

    "kind": "custom",

    "version": "2",

    "rules": [

      {

        "id": "<CUSTOM_RULE_ID_1>",

        "version": "1",

        "action": "challenge",

        "expression": "(ip.src.country in {\"GB\" \"FR\"} and cf.bot_management.score < 20 and not cf.bot_management.verified_bot)",

        "description": "challenge GB and FR based on bot score",

        "last_updated": "2021-03-18T18:25:08.122758Z",

        "ref": "<CUSTOM_RULE_REF_1>",

        "enabled": true

      },

      {

        "id": "<CUSTOM_RULE_ID_2>",

        "version": "1",

        "action": "challenge",

        "expression": "not http.request.uri.path matches \"^/api/.*$\"",

        "description": "challenge not /api",

        "last_updated": "2021-03-18T18:25:08.122758Z",

        "ref": "<CUSTOM_RULE_REF_2>",

        "enabled": true

      }

    ],

    "last_updated": "2021-03-18T18:25:08.122758Z",

    "phase": "http_request_firewall_custom"

  },

  "success": true,

  "errors": [],

  "messages": []

}


```

## Update rules

To update one or more rules in a custom ruleset, use the [Update an account or zone ruleset](https://developers.cloudflare.com/api/resources/rulesets/methods/update/) operation. Include the ID of the rules you want to modify in the rules array and add the fields you wish to update. The request replaces the entire ruleset with a new version. Therefore, you must include the ID of all the rules you wish to keep.

The following `PUT` request edits one rule in a custom ruleset at the account level and updates the execution order of the rules.

The response will include the modified custom ruleset. Note that the updated rule and ruleset version number increment.

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

Update an account ruleset

```

curl "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/rulesets/$RULESET_ID" \

  --request PUT \

  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \

  --json '{

    "rules": [

        {

            "id": "<CUSTOM_RULE_ID_2>",

            "expression": "not http.request.uri.path matches \"^/api/.*$\"",

            "action": "js_challenge",

            "description": "js_challenge when not /api"

        },

        {

            "id": "<CUSTOM_RULE_ID_1>"

        }

    ]

  }'


```

```

{

  "result": {

    "id": "<CUSTOM_RULESET_ID>",

    "name": "Custom Ruleset 1",

    "kind": "custom",

    "version": "3",

    "rules": [

      {

        "id": "<CUSTOM_RULE_ID_2>",

        "version": "2",

        "action": "js_challenge",

        "expression": "not http.request.uri.path matches \"^/api/.*$\"",

        "description": "js_challenge when not /api",

        "last_updated": "2021-03-18T18:30:08.122758Z",

        "ref": "<CUSTOM_RULE_ID_2>",

        "enabled": true

      },

      {

        "id": "<CUSTOM_RULE_ID_1>",

        "version": "1",

        "action": "challenge",

        "expression": "(ip.src.country in {\"GB\" \"FR\"} and cf.bot_management.score < 20 and not cf.bot_management.verified_bot)",

        "description": "challenge GB and FR based on bot score",

        "last_updated": "2021-03-18T18:25:08.122758Z",

        "ref": "<CUSTOM_RULE_ID_1>",

        "enabled": true

      }

    ],

    "last_updated": "2021-03-18T18:30:08.122758Z",

    "phase": "http_request_firewall_custom"

  },

  "success": true,

  "errors": [],

  "messages": []

}


```

Warning

The request above completely replaces the list of rules in the ruleset. If you omit an existing rule from the `rules` array, it will not appear in the new version of the ruleset.

```json
{"@context":"https://schema.org","@type":"BreadcrumbList","itemListElement":[{"@type":"ListItem","position":1,"item":{"@id":"/directory/","name":"Directory"}},{"@type":"ListItem","position":2,"item":{"@id":"/ruleset-engine/","name":"Ruleset Engine"}},{"@type":"ListItem","position":3,"item":{"@id":"/ruleset-engine/custom-rulesets/","name":"Work with custom rulesets"}},{"@type":"ListItem","position":4,"item":{"@id":"/ruleset-engine/custom-rulesets/add-rules-ruleset/","name":"Add rules to a custom ruleset"}}]}
```
