#!/usr/bin/env bash

# =================================================================================================
# cf-inc v0.5.0
# =================================================================================================

API_URL="https://api.cloudflare.com"

# =====================================
# -- debug_jsons
# =====================================
_debug_json () {
    if [[ $DEBUG_JSON == "1" ]]; then
        echo -e "${CCYAN}** Outputting JSON ${*}${NC}"
        echo "${@}" | jq
    fi
}

# =====================================
# -- cf_api <$REQUEST> <$API_PATH>
# =====================================
function cf_api() {    
    # -- Run cf_api with tokens
    _debug "function:${FUNCNAME[0]}"
    _debug "Running cf_api() with ${*}"
    
    if [[ -n $API_TOKEN ]]; then        
        CURL_HEADERS=("-H" "Authorization: Bearer ${API_TOKEN}")
        _debug "Using \$API_TOKEN as token. \$CURL_HEADERS: ${CURL_HEADERS[*]}"
        REQUEST="$1"
        API_PATH="$2"
        CURL_OUTPUT=$(mktemp)    
    elif [[ -n $API_ACCOUNT ]]; then                    
            CURL_HEADERS=("-H" "X-Auth-Key: ${API_APIKEY}" -H "X-Auth-Email: ${API_ACCOUNT}")
            _debug "Using \$API_APIKEY as token. \$CURL_HEADERS: ${CURL_HEADERS[*]}"
            REQUEST="$1"
            API_PATH="$2"
            CURL_OUTPUT=$(mktemp)
    else
        _error "No API Token or API Key found...major error...exiting"
        exit 1
    fi
	
    _debug "Running curl -s --request $REQUEST --url "${API_URL}${API_PATH}" "${CURL_HEADERS[*]}""
    [[ $DEBUG == "1" ]] && set -x
    CURL_EXIT_CODE=$(curl -s -w "%{http_code}" --request "$REQUEST" \
        --url "${API_URL}${API_PATH}" \
        "${CURL_HEADERS[@]}" \
        --output "$CURL_OUTPUT" "${EXTRA[@]}")
    [[ $DEBUG == "1" ]] && set +x
    API_OUTPUT=$(<"$CURL_OUTPUT")
    _debug_json "$API_OUTPUT"
    rm "$CURL_OUTPUT"

		
	if [[ $CURL_EXIT_CODE == "200" ]]; then
	    MESG="Success from API: $CURL_EXIT_CODE"
        _debug "$MESG"
        _debug "$API_OUTPUT"    
	else
        MESG="Error from API: $CURL_EXIT_CODE"
        _error "$MESG"
        _debug "$API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- test_creds $ACCOUNT $API_KEY
# =====================================
function test_creds () {
    if [[ -n $API_TOKEN ]]; then
        _debug "function:${FUNCNAME[0]}"
        _running "Testing credentials via CLI"
        cf_api GET /client/v4/user/tokens/verify
        API_OUTPUT=$(echo $API_OUTPUT | jq '.messages[0].message' )
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

# -- test_api_token $TOKEN
function test-token () {    
    _debug "function:${FUNCNAME[0]}"
    _running "Testing token via CLI"        
    cf_api GET /client/v4/user/tokens/verify
    API_OUTPUT=$(echo $API_OUTPUT | jq '.messages[0].message' )
    [[ $CURL_EXIT_CODE == "200" ]] && _success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
}

# =====================================
# -- get_zone_id
# =====================================
function get_zone_id () {
    _debug "function:${FUNCNAME[0]}"
    _running "Getting zone_id for ${DOMAIN_NAME}"
    cf_api GET /client/v4/zones?name=${DOMAIN_NAME}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        ZONE_ID=$(echo $API_OUTPUT | jq -r '.result[0].id' )
        if [[ $ZONE_ID != "null" ]]; then            
            _success "Got ZoneID ${ZONE_ID} for ${DOMAIN_NAME}"
        else
            _error "Couldn't get ZoneID, using -z to provide ZoneID or give access read:zone access to your token"
            echo "$MESG - $AP_OUTPUT"
            exit 1
        fi
    else
        _error "Couldn't get ZoneID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        echo "$MESG - $AP_OUTPUT"
        exit 1
    fi
}
# =====================================
# -- get_zone_idv2 $DOMAIN_NAME
# =====================================
function get_zone_idv2 () {
    DOMAIN_NAME=$1
    _debug "function:${FUNCNAME[0]}"    
    cf_api GET /client/v4/zones?name=${DOMAIN_NAME}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        ZONE_ID=$(echo $API_OUTPUT | jq -r '.result[0].id' )
        if [[ $ZONE_ID != "null" ]]; then            
            echo $ZONE_ID
        else
            _debug "Couldn't get ZoneID, using -z to provide ZoneID or give access read:zone access to your token"
            _debug "$MESG - $AP_OUTPUT"
            exit 1
        fi
    else
        _debug "Couldn't get ZoneID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        _debug "$MESG - $AP_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- get_account_id_from_domain $DOMAIN
# =====================================
get_account_id_from_domain() {
    local DOMAIN_NAME=$1
     cf_api GET /client/v4/zones?name=${DOMAIN_NAME}
    ACCOUNT_ID=$(echo $API_OUTPUT | jq -r '.result[0].account.id')
    if [[ $ACCOUNT_ID == "null" ]]; then
        _error "No account id found for ${DOMAIN_NAME}"
        return 1
    else
        echo $ACCOUNT_ID
    fi
}

# =====================================
# -- get_account_id_from_zone $ZONE_ID
# =====================================
function get_account_id_from_zone () {
    ZONE_ID=$1
    _debug "function:${FUNCNAME[0]}"    
    _debug "Getting account_id for ${ZONE_ID}"
    cf_api GET /client/v4/zones/${ZONE_ID}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        ACCOUNT_ID=$(echo $API_OUTPUT | jq -r '.result.account.id' )        
        if [[ $ACCOUNT_ID != "null" ]]; then            
            echo $ACCOUNT_ID
        else
            _debug "Couldn't get AccountID, using -a to provide AccountID or give access read:account access to your token"
            _debug "$MESG - $AP_OUTPUT"
            exit 1
        fi
    else
        _debug "Couldn't get AccountID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        _debug "$MESG - $AP_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- get_permissions
# =====================================
get_permissions () {
    _debug "Running get_permissions"
    cf_api GET /client/v4/user/tokens/permission_groups
}
