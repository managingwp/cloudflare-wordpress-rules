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
    
