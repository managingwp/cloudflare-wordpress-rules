# =============================================================================
# -- Functions
# =============================================================================

# =====================================
# -- test_creds $ACCOUNT $API_KEY
# =====================================
function test_creds () {
    if [[ -n $API_TOKEN ]]; then
        _debug "function:${FUNCNAME[0]}"
        _running "Testing credentials via CLI"
        cf_api GET /client/v4/user/tokens/verify
        API_OUTPUT=$(echo "$API_OUTPUT" | jq '.messages[0].message' )
        [[ $CURL_EXIT_CODE == "200" ]] && _success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
    elif [[ -n $API_APIKEY ]]; then
        _debug "function:${FUNCNAME[0]}"
        _running "Testing credentials via CLI"
        cf_api GET /client/v4/user
        API_OUTPUT=$(echo $API_OUTPUT | jq '.messages[0].message' )
        [[ $CURL_EXIT_CODE == "200" ]] && _success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
    else
        _error "No API Token or API Key found, exiting"
        exit 1
    fi
}

# =====================================
# -- test_api_token $TOKEN
# =====================================
function test-token () {    
    _debug "function:${FUNCNAME[0]}"
    _running "Testing token via CLI"        
    cf_api GET /client/v4/user/tokens/verify
    API_OUTPUT=$(echo $API_OUTPUT | jq '.messages[0].message' )
    [[ $CURL_EXIT_CODE == "200" ]] && _success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
}

# =====================================
# -- get_permissions
# =====================================
get_permissions () {
    _debug "Running get_permissions"
    cf_api GET /client/v4/user/tokens/permission_groups
}
# =====================================
# -- list_tokens
# =====================================
list_tokens () {
    _debug "Running list_tokens"
    cf_api GET /client/v4/user/tokens
}

# =====================================
# -- create_token $DOMAIN $TOKEN_NAME
# =====================================
create_token () {
    _debug "function:${FUNCNAME[0]}" 
    local DOMAIN_NAME=$1 TOKEN_NAME=$2 CF_ZONE_ID
    EXTRA=()

    _running2 "Getting Zone ID for $DOMAIN_NAME"
    CF_ZONE_ID="$(_get_zone_id $DOMAIN_NAME)"
    if [[ -z $CF_ZONE_ID ]]; then
        _error "No Zone ID found for $DOMAIN_NAME"
        exit 1
    else
        _success "Zone ID found for $DOMAIN_NAME: $CF_ZONE_ID"
    fi
    local ZONE_ID_JSON=("com.cloudflare.api.account.zone.${CF_ZONE_ID}")
    EXTRA=('
 {
 	"name": "'${DOMAIN_NAME}' '${TOKEN_NAME}'",
 	"policies": [
         {
 			"effect": "allow",
 			"resources": {
 				"com.cloudflare.api.account.*": "*"
 			},
 			"permission_groups": [{
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
 				"'"${ZONE_ID_JSON[@]}"'": "*"
 			},
 			"permission_groups": [{
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
 				}
 			]
 		}
 	],
 	"condition": {}
 }')
    _debug "Extra: ${EXTRA[*]}"
    _running2 "Creating token ${TOKEN_NAME} for ${DOMAIN_NAME}"
    API_OUTPUT=$(_cf_api POST-JSON /client/v4/user/tokens "${EXTRA[@]}")
    
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        NEW_API_TOKEN=$(echo $API_OUTPUT | jq '.result.value')
        _success "New API Token -- ${TOKEN_NAME}: ${NEW_API_TOKEN}"
    else
        _error "Error creating token"
        echo "$API_OUTPUT"
        return 1
    fi
}