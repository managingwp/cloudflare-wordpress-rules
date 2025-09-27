#!/usr/bin/env bash
# =============================================================================
# -- Functions
# =============================================================================

# ==================================
# -- list_tokens $DOMAIN_NAME
# ===================================
list_tokens () {
    _debug "Running list_tokens"
    if [[ $ACCOUNT_OWNED ]]; then        
        _running2 "Listing tokens for $DOMAIN_NAME"        
        _cf_zone_accountid $DOMAIN_NAME
        _running3 "Found AccountID: $ACCOUNT_ID for $DOMAIN_NAME"
        cf_api GET /client/v4/accounts/${ACCOUNT_ID}/tokens
        echo "$API_OUTPUT" | jq '.result[] | {id: .id, name: .name, created_at: .created_at, modified_at: .modified_at}'
    else
        _running2 "Listing tokens for user"
        cf_api GET /client/v4/user/tokens
        echo "$API_OUTPUT" | jq '.result[] | {id: .id, name: .name, created_at: .created_at, modified_at: .modified_at}'
    fi
}

# ==================================
# -- _cf_spc_token_exists $DOMAIN $TOKEN_NAME
# ==================================
_cf_spc_token_exists () {
    _debug "function:${FUNCNAME[0]}"
    local DOMAIN_NAME="${1}"
    local TOKEN_NAME="${2}"
    local ZONE_ID
    local TOKEN_ID

    _running2 "Checking if token $TOKEN_NAME exists for $DOMAIN_NAME"
    
    # -- Get ZoneID
    ZONE_ID=$(_cf_zone_id "$DOMAIN_NAME") # Get zone id
    [[ -z $ZONE_ID ]] && { _error "No zone id found for $DOMAIN_NAME"; exit 1;} # No zone id, exit
    _debug "ZONE_ID: $ZONE_ID"
    
    # -- Get TokenID
    if [[ -n $ACCOUNT_OWNED ]]; then
        _running2 "Getting token id for account owned"
        TOKEN_ID=$(_cf_spc_get_token_id_from_zone "$ZONE_ID" "$TOKEN_NAME")
        [[ -z $TOKEN_ID ]] && { _error "No token id found for $DOMAIN_NAME"; exit 1;} # No token id, exit
        _debug "TOKEN_ID: $TOKEN_ID"
        _success "Token id found for $DOMAIN_NAME: $TOKEN_ID"
    else
        _running2 "Getting token id for user"
        TOKEN_ID=$(_cf_get_token_id_from_user $TOKEN_NAME)
        _debug "TOKEN_ID: $TOKEN_ID"
    fi

    _debug "TOKEN_ID: $TOKEN_ID"
    # -- Check if token exists
    if [[ -n $TOKEN_ID ]]; then
        _debug "Token exists"
        return 0
    else
        _debug "Token does not exist"
        return 1
    fi
}

# ==================================
# -- _cf_spc_get_token_id_from_zone $ZONE_ID $TOKEN_NAME $QUIET
# ==================================
_cf_spc_get_token_id_from_zone () {
    _debug "function:${FUNCNAME[0]} - $@"
    local ZONE_ID=${1}
    local TOKEN_NAME=${2}
    local QUIET=${3:-0}
    local TOKEN_ID
    _debug "ZONE_ID: $ZONE_ID TOKEN_NAME: $TOKEN_NAME QUIET: $QUIET"

    # -- Get ACCOUNT_OWNED_ID        
    ACCOUNT_OWNED_ID="$(_cf_get_account_id_from_zone $ZONE_ID)"
    _debug "ACCOUNT_OWNED_ID: $ACCOUNT_OWNED_ID"
    [[ -z $ACCOUNT_OWNED_ID ]] && { _error "No account id found for $ZONE_ID"; exit 1;} # No account id, exit

    # -- Get TokenID
    cf_api GET /client/v4/accounts/${ACCOUNT_OWNED_ID}/tokens    
    #echo "$API_OUTPUT" | jq '.result[] | {id: .id, name: .name, created_at: .created_at, modified_at: .modified_at}'
    TOKEN_ID=$(echo "$API_OUTPUT" | jq -r --arg name "$TOKEN_NAME" '.result[] | select(.name == $name) | {id: .id, name: .name, status: .status, issued_on: .issued_on, modified_on: .modified_on, last_used_on: .last_used_on}')
    _debug "TOKEN_ID: $TOKEN_ID"
    
    if [[ -n $TOKEN_ID ]]; then
        _debug "Token id found: $TOKEN_ID"
        [[ $QUIET -eq 0 ]] && echo "$TOKEN_ID" && return 0
        [[ $QUIET -eq 1 ]] && echo "$TOKEN_ID" && return 0        
    else
        _debug "Token id not found"
        return 1
    fi
}

# ==================================
# -- _cf_spc_create_token $DOMAIN_NAME $TOKEN_NAME
# ==================================
_cf_spc_create_token () {
    _debug "function:${FUNCNAME[0]}"    
    local DOMAIN_NAME=${1}
    local TOKEN_NAME=${2}
    local ZONE_ID
    _debug "DOMAIN_NAME: $DOMAIN_NAME TOKEN_NAME: $TOKEN_NAME"

    # -- Get ZoneID
    ZONE_ID=$(_cf_zone_id $DOMAIN_NAME) # Get zone id
        [[ -z $ZONE_ID ]] && { _error "No zone id found for $DOMAIN_NAME"; exit 1;} # No zone id, exit
    _debug "ZONE_ID: $ZONE_ID"
    

    [[ -z $TOKEN_NAME ]] && TOKEN_NAME="${DOMAIN_NAME}-spc"
    _running2 "Creating token for $DOMAIN_NAME with id $ZONE_ID with token name $TOKEN_NAME"
        
    _debug "Creating token for $DOMAIN_NAME with id $ZONE_ID"
    if [[ -n $ACCOUNT_OWNED ]]; then        
        _running2 "Getting account id for account owned"
        ACCOUNT_OWNED_ID=$(_cf_get_account_id_from_zone $ZONE_ID)
        _debug "ACCOUNT_OWNED_ID: $ACCOUNT_OWNED_ID"
        if [[ -z $ACCOUNT_OWNED_ID ]]; then
            _error "No account id found for $ZONE_ID"
            exit 1
        fi

        _debug "Creating token for id $ZONE_ID using account id $ACCOUNT_OWNED_ID"
        CF_API_ACCOUNT="com.cloudflare.api.account.${ACCOUNT_OWNED_ID}\":\"*"
    else
        _running "Creating token for user"
        CF_API_ACCOUNT="com.cloudflare.api.account.*\":\"*"
    fi

    _running2 "Checking if token exists for $DOMAIN_NAME"
    TOKEN_EXISTS=$(_cf_spc_get_token_id_from_zone $ZONE_ID $TOKEN_NAME 1)    
    [[ $? -eq 0 ]] && { _error "Token already exists for $DOMAIN_NAME"; return 1;} # Token already exists, exit
    _debug "TOKEN_EXISTS: $TOKEN_EXISTS"
    
    # -- Create token
    _cf_spc_create_token_api "$DOMAIN_NAME" "$ZONE_ID" "$TOKEN_NAME"
    if [[ $? -ne 0 ]]; then
        _error "Error creating token for $DOMAIN_NAME"
        return 1
    fi
}
# ===================================
# -- _cf_spc_create_token_api $DOMAIN_NAME $ZONE_ID $TOKEN_NAME
# ===================================
function _cf_spc_create_token_api () {
    _debug "function:${FUNCNAME[0]}"
    local DOMAIN_NAME=${1}
    local ZONE_ID=${2}
    local TOKEN_NAME=${3}

    _debug "Adding permission to DOMAIN_NAME: $DOMAIN_NAME ZONE_ID: $ZONE_ID TOKEN_NAME: $TOKEN_NAME"    
    ZONE_ID_JSON=("com.cloudflare.api.account.zone.${ZONE_ID}")
    EXTRA=(-H 'Content-Type: application/json' \
     --data '
 {
  "name": "'${TOKEN_NAME}'",
  "policies": [
    {
      "effect": "allow",
      "resources": {
        "'${CF_API_ACCOUNT}'"
      },
      "permission_groups": [
        {
          "id": "e086da7e2179491d91ee5f35b3ca210a",
          "name": "Workers Scripts Write"
        },
        {
          "id": "c1fde68c7bcc44588cbb6ddbc16d6480",
          "name": "Account Settings Read"
        }
      ]
    },
    {
      "effect": "allow",
      "resources": {
        "'${ZONE_ID_JSON[@]}'": "*"
      },
      "permission_groups": [
        {
          "id": "e17beae8b8cb423a99b1730f21238bed",
          "name": "Cache Purge"
        },
        {
          "id": "ed07f6c337da4195b4e72a1fb2c6bcae",
          "name": "Page Rules Write"
        },
        {
          "id": "3030687196b94b638145a3953da2b699",
          "name": "Zone Settings Write"
        },
        {
          "id": "e6d2666161e84845a636613608cee8d5",
          "name": "Zone Write"
        },
        {
          "id": "28f4b596e7d643029c524985477ae49a",
          "name": "Workers Routes Write"
        },
        {
          "id": "9c88f9c5bce24ce7af9a958ba9c504db",
          "name": "Zone Analytics Read"
        },
        {
          "id": "c8fed203ed3043cba015a93ad1616f1f",
          "name": "Zone Read"
        },
        {
          "id": "3030687196b94b638145a3953da2b699",
          "name": "Zone Settings Write"
        },
        {
          "id": "82e64a83756745bbbb1c9c2701bf816b",
          "name": "DNS Read"
        },
        {
          "id": "e17beae8b8cb423a99b1730f21238bed",
          "name": "Zone Cache Purge"
        },
        {
          "id": "9ff81cbbe65c400b97d92c3c1033cab6",
          "name": "Zone Cache Rules Edit"
        },
        {
          "id": "0ac90a90249747bca6b047d97f0803e9",
          "name": "Zone Transform Rules Write"
        }
      ]
    }
  ],
  "condition": {}
}')
    _debug "EXTRA: ${EXTRA[*]}"
    
    if [[ -n $ACCOUNT_OWNED ]]; then
        cf_api POST /client/v4/accounts/${ACCOUNT_OWNED_ID}/tokens "${EXTRA[@]}"
    else
        cf_api POST /client/v4/user/tokens "${EXTRA[@]}"
    fi
    
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        NEW_API_TOKEN=$(echo $API_OUTPUT | jq '.result.value')
        _success "New API Token -- ${TOKEN_NAME}: ${NEW_API_TOKEN}"
        [[ $QUIET == 1 ]] && echo "${DOMAIN_NAME},${TOKEN_NAME},${NEW_API_TOKEN}"
    else        
        echo "$MESG - $API_OUTPUT"
        exit 1
    fi
}

# ==================================
# -- _cf_app_cf_create_token $DOMAIN_NAME $TOKEN_NAME
# ==================================
_cf_app_cf_create_token () {
    _debug "function:${FUNCNAME[0]}"    
    local DOMAIN_NAME=${1}
    local TOKEN_NAME=${2}
    local ZONE_ID
    _debug "DOMAIN_NAME: $DOMAIN_NAME TOKEN_NAME: $TOKEN_NAME"

    # -- Get ZoneID
    ZONE_ID=$(_cf_zone_id $DOMAIN_NAME) # Get zone id
        [[ -z $ZONE_ID ]] && { _error "No zone id found for $DOMAIN_NAME"; exit 1;} # No zone id, exit
    _debug "ZONE_ID: $ZONE_ID"
    
    [[ -z $TOKEN_NAME ]] && TOKEN_NAME="${DOMAIN_NAME}-app-cf"
    _running2 "Creating App for Cloudflare token for $DOMAIN_NAME with id $ZONE_ID with token name $TOKEN_NAME"
        
    _debug "Creating token for $DOMAIN_NAME with id $ZONE_ID"
    if [[ -n $ACCOUNT_OWNED ]]; then        
        _running2 "Getting account id for account owned"
        ACCOUNT_OWNED_ID=$(_cf_get_account_id_from_zone $ZONE_ID)
        _debug "ACCOUNT_OWNED_ID: $ACCOUNT_OWNED_ID"
        if [[ -z $ACCOUNT_OWNED_ID ]]; then
            _error "No account id found for $ZONE_ID"
            exit 1
        fi

        _debug "Creating token for id $ZONE_ID using account id $ACCOUNT_OWNED_ID"
        CF_API_ACCOUNT="com.cloudflare.api.account.${ACCOUNT_OWNED_ID}\":\"*"
    else
        _running "Creating token for user"
        CF_API_ACCOUNT="com.cloudflare.api.account.*\":\"*"
    fi

    _running2 "Checking if token exists for $DOMAIN_NAME"
    TOKEN_EXISTS=$(_cf_spc_get_token_id_from_zone $ZONE_ID $TOKEN_NAME 1)    
    [[ $? -eq 0 ]] && { _error "Token already exists for $DOMAIN_NAME"; return 1;} # Token already exists, exit
    _debug "TOKEN_EXISTS: $TOKEN_EXISTS"
    
    # -- Create token
    _cf_app_cf_create_token_api "$DOMAIN_NAME" "$ZONE_ID" "$TOKEN_NAME"
    if [[ $? -ne 0 ]]; then
        _error "Error creating token for $DOMAIN_NAME"
        return 1
    fi
}

# ===================================
# -- _cf_app_cf_create_token_api $DOMAIN_NAME $ZONE_ID $TOKEN_NAME
# ===================================
function _cf_app_cf_create_token_api () {
    _debug "function:${FUNCNAME[0]}"
    local DOMAIN_NAME=${1}
    local ZONE_ID=${2}
    local TOKEN_NAME=${3}

    _debug "Adding App for Cloudflare permissions to DOMAIN_NAME: $DOMAIN_NAME ZONE_ID: $ZONE_ID TOKEN_NAME: $TOKEN_NAME"    
    ZONE_ID_JSON=("com.cloudflare.api.account.zone.${ZONE_ID}")
    EXTRA=(-H 'Content-Type: application/json' \
     --data '
 {
  "name": "'${TOKEN_NAME}'",
  "policies": [
    {
      "effect": "allow",
      "resources": {
        "'${CF_API_ACCOUNT}'"
      },
      "permission_groups": [
        {
          "id": "1e13c5124ca64b72b1969a67e8829049",
          "name": "Access: Apps and Policies Write"
        },
        {
          "id": "26bc23f853634eb4bff59983b9064fde",
          "name": "Access: Organizations, Identity Providers, and Groups Read"
        },
        {
          "id": "b89a480218d04ceb98b4fe57ca29dc1f",
          "name": "Account Analytics Read"
        },
        {
          "id": "f3604047d46144d2a3e9cf4ac99d7f16",
          "name": "Allow Request Tracer Read"
        },
        {
          "id": "7cf72faf220841aabcfdfab81c43c4f6",
          "name": "Billing Read"
        },
        {
          "id": "df1577df30ee46268f9470952d7b0cdf",
          "name": "Intel Read"
        },
        {
          "id": "755c05aa014b4f9ab263aa80b8167bd8",
          "name": "Turnstile Sites Write"
        },
        {
          "id": "bf7481a1826f439697cb59a20b22293e",
          "name": "Workers R2 Storage Write"
        },
        {
          "id": "e086da7e2179491d91ee5f35b3ca210a",
          "name": "Workers Scripts Write"
        }
      ]
    },
    {
      "effect": "allow",
      "resources": {
        "'${ZONE_ID_JSON[@]}'": "*"
      },
      "permission_groups": [
        {
          "id": "9c88f9c5bce24ce7af9a958ba9c504db",
          "name": "Analytics Read"
        },
        {
          "id": "3b94c49258ec4573b06d51d99b6416c0",
          "name": "Bot Management Write"
        },
        {
          "id": "e17beae8b8cb423a99b1730f21238bed",
          "name": "Cache Purge"
        },
        {
          "id": "9ff81cbbe65c400b97d92c3c1033cab6",
          "name": "Cache Settings Write"
        },
        {
          "id": "43137f8d07884d3198dc0ee77ca6e79b",
          "name": "Firewall Services Write"
        },
        {
          "id": "ed07f6c337da4195b4e72a1fb2c6bcae",
          "name": "Page Rules Write"
        },
        {
          "id": "c03055bc037c4ea9afb9a9f104b7b721",
          "name": "SSL and Certificates Write"
        },
        {
          "id": "e6d2666161e84845a636613608cee8d5",
          "name": "Zone Write"
        },
        {
          "id": "3030687196b94b638145a3953da2b699",
          "name": "Zone Settings Write"
        },
        {
          "id": "fb6778dc191143babbfaa57993f1d275",
          "name": "Zone WAF Write"
        }
      ]
    }
  ],
  "condition": {}
}')
    _debug "EXTRA: ${EXTRA[*]}"
    
    if [[ -n $ACCOUNT_OWNED ]]; then
        cf_api POST /client/v4/accounts/${ACCOUNT_OWNED_ID}/tokens "${EXTRA[@]}"
    else
        cf_api POST /client/v4/user/tokens "${EXTRA[@]}"
    fi
    
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        NEW_API_TOKEN=$(echo $API_OUTPUT | jq '.result.value')
        _success "New App for Cloudflare API Token -- ${TOKEN_NAME}: ${NEW_API_TOKEN}"
        [[ $QUIET == 1 ]] && echo "${DOMAIN_NAME},${TOKEN_NAME},${NEW_API_TOKEN}"
    else        
        echo "$MESG - $API_OUTPUT"
        exit 1
    fi
}

# ==================================
# -- _cf_spc_test_perms perms $DOMAIN_NAME
# ==================================
_cf_spc_test_perms () {
    _debug "function:${FUNCNAME[0]}"
    local DOMAIN_NAME=${1}    
    local ZONE_ID
    _debug "DOMAIN_NAME: $DOMAIN_NAME"

    # -- Get ZoneID
    ZONE_ID=$(_cf_zone_id $DOMAIN_NAME) # Get zone id
        [[ -z $ZONE_ID ]] && { _error "No zone id found for $DOMAIN_NAME"; exit 1;} # No zone id, exit    
    _running2 "Got Zone id for $DOMAIN_NAME: $ZONE_ID"

    # -- Get ACCOUNT_OWNED_ID
    if [[ -n $ACCOUNT_OWNED ]]; then
      ACCOUNT_OWNED_ID="$(_cf_get_account_id_from_zone $ZONE_ID)"    
      _running2 "Got Account id for $DOMAIN_NAME: $ACCOUNT_OWNED_ID"
      [[ -z $ACCOUNT_OWNED_ID ]] && { _error "No account id found for $ZONE_ID"; exit 1;} # No account id, exit
      cf_api GET /client/v4/accounts/${ACCOUNT_OWNED_ID}/tokens
    else
      cf_api GET /client/v4/user/tokens
    fi
    
    # -- Check if we can create tokens
    _debug "Checking if we can create tokens for $DOMAIN_NAME"
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _success "We can create tokens for $DOMAIN_NAME"
        echo "$API_OUTPUT" | jq '.result[]'
        return 0
    else
        _error "We cannot create tokens for $DOMAIN_NAME"
        return 1
    fi
}

# =====================================
# -- _cf_spc_test_token $DOMAIN $TOKEN
# =====================================
_cf_spc_test_token () {
    _debug "function:${FUNCNAME[0]}"
    DOMAIN="${1}"
    TOKEN="${2}"
    _debug "DOMAIN: ${DOMAIN} TOKEN: ${API_TOKEN}"
    if [[ -z $TOKEN ]]; then
        _error "No token provided"
        return 1
    fi

    # Get accountID of domain
    _running2 "Getting account ID for $DOMAIN"
    ACCOUNT_ID="$(_cf_zone_accountid "$DOMAIN")"
    if [[ -z $ACCOUNT_ID ]]; then
        _error "No account ID found for $DOMAIN"
        return 1
    fi
    _debug "ACCOUNT_ID: $ACCOUNT_ID"


    API_TOKEN=$TOKEN
    _running2 "Testing token: $API_TOKEN"
    cf_api GET /client/v4/accounts/${ACCOUNT_ID}/tokens/verify
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _success "Token is valid"
        echo "$API_OUTPUT" | jq '.result'
        return 0
    else
        _error "Token is invalid"
        echo "$API_OUTPUT"
        return 1
    fi
}

# ==================================
# -- list_permission_groups
# ===================================
list_permission_groups () {
    _debug "Running list_permission_groups"
    _running2 "Listing all available permission groups for API tokens"
    
    cf_api GET /client/v4/user/tokens/permission_groups
    
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _success "Successfully retrieved permission groups"
        echo "$API_OUTPUT" | jq -r '
        .result[] | 
        "ID: " + .id + " | Name: " + .name + " | Scopes: " + (.scopes | join(", "))
        ' | sort
        
        echo ""
        _running2 "Permission groups in table format:"
        echo "$API_OUTPUT" | jq -r '
        ["ID", "Name", "Scopes"],
        ["----", "----", "------"],
        (.result[] | [.id, .name, (.scopes | join(", "))]) | @tsv
        ' | column -t
    else
        _error "Failed to retrieve permission groups"
        echo "$API_OUTPUT"
        return 1
    fi
}

# ==================================
# -- list_token_permissions $TOKEN_ID
# ===================================
list_token_permissions () {
    _debug "Running list_token_permissions"
    local TOKEN_ID="$1"
    _running2 "Listing permissions for token ID: $TOKEN_ID"
    
    # Check if this is an account-owned token lookup
    if [[ -n $ACCOUNT_OWNED && -n $DOMAIN_NAME ]]; then
        _running2 "Looking up account token for domain: $DOMAIN_NAME"
        
        # Get zone and account ID
        ZONE_ID=$(_cf_zone_id "$DOMAIN_NAME")
        if [[ -n $ZONE_ID ]]; then
            ACCOUNT_OWNED_ID=$(_cf_get_account_id_from_zone "$ZONE_ID")
            if [[ -n $ACCOUNT_OWNED_ID ]]; then
                _running3 "Using account ID: $ACCOUNT_OWNED_ID"
                cf_api GET /client/v4/accounts/"$ACCOUNT_OWNED_ID"/tokens/"$TOKEN_ID"
                
                if [[ $CURL_EXIT_CODE == "200" ]]; then
                    _success "Successfully retrieved account token permissions"
                    _display_token_info
                    return 0
                fi
            fi
        fi
        _error "Failed to retrieve account token permissions for token ID: $TOKEN_ID"
        echo "$API_OUTPUT"
        return 1
    else
        # Try user tokens first
        cf_api GET /client/v4/user/tokens/"$TOKEN_ID"
        
        if [[ $CURL_EXIT_CODE == "200" ]]; then
            _success "Successfully retrieved user token permissions"
            _display_token_info
            return 0
        else
            # If user token fetch fails and we have a domain, try account tokens
            if [[ -n $DOMAIN_NAME ]]; then
                _running2 "Token not found in user tokens, trying account tokens for domain: $DOMAIN_NAME"
                
                # Get zone and account ID
                ZONE_ID=$(_cf_zone_id "$DOMAIN_NAME")
                if [[ -n $ZONE_ID ]]; then
                    ACCOUNT_OWNED_ID=$(_cf_get_account_id_from_zone "$ZONE_ID")
                    if [[ -n $ACCOUNT_OWNED_ID ]]; then
                        cf_api GET /client/v4/accounts/"$ACCOUNT_OWNED_ID"/tokens/"$TOKEN_ID"
                        
                        if [[ $CURL_EXIT_CODE == "200" ]]; then
                            _success "Successfully retrieved account token permissions"
                            _display_token_info
                            return 0
                        fi
                    fi
                fi
            fi
            
            _error "Failed to retrieve token permissions for token ID: $TOKEN_ID"
            if [[ -z $DOMAIN_NAME ]]; then
                _error "Hint: If this is an account-owned token, try providing a domain with -d <domain>"
            fi
            echo "$API_OUTPUT"
            return 1
        fi
    fi
}

# ==================================
# -- _display_token_info (helper function)
# ===================================
_display_token_info () {
    # Display basic token info
    echo "$API_OUTPUT" | jq -r '
    .result | 
    "Token Name: " + .name + "\n" +
    "Status: " + .status + "\n" +
    "Created: " + .issued_on + "\n" +
    "Modified: " + .modified_on + "\n" +
    "Last Used: " + (.last_used_on // "Never")
    '
    
    echo ""
    _running2 "Token Policies:"
    
    # Display policies in a readable format
    echo "$API_OUTPUT" | jq -r '
    .result.policies[] | 
    "Effect: " + .effect + "\n" +
    "Resources: " + (.resources | to_entries | map(.key + ": " + .value) | join(", ")) + "\n" +
    "Permission Groups:" +
    (.permission_groups[] | "\n  - " + .name + " (ID: " + .id + ")")
    ' | sed 's/^/  /'
    
    echo ""
    _running2 "Token Policies in table format:"
    echo "$API_OUTPUT" | jq -r '
    ["Permission Group ID", "Permission Group Name", "Resource"],
    ["--------------------", "--------------------", "--------"],
    (.result.policies[] as $policy | 
     ($policy.resources | to_entries[0].key) as $resource |
     $policy.permission_groups[] | 
     [.id, .name, $resource]) | @tsv
    ' | column -t
}