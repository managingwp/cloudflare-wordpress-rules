#!/usr/bin/env bash
# ==================================================
# -- Cloudflare settings default
# ==================================================
declare -A CF_SETTINGS

# Add settings to the array
CF_SETTINGS["security_level"]="Security Level"
CF_SETTINGS["challenge_ttl"]="Challenge TTL"
CF_SETTINGS["browser_check"]="Browser Check"
CF_SETTINGS["always_use_https"]="Always Use HTTPS"
CF_SETTINGS["min_tls_version"]="Minimum TLS Version"

CF_SETTINGS_ALLOWED=("security_level" "challenge_ttl" "browser_check" "always_use_https")
# -- Challenge TTL
# Defaults for challenge ttl -
CF_DEFAULTS_CHALLENGE_TTL=(300 900 1800 2700 3600 7200 10800 14400 28800 57600 86400 604800 2592000 31536000)
CF_DEFAULTS_SECURITY_LEVEL=("essentially_off" "low" "medium" "high" "under_attack")
CF_DEFAULTS_BROWSER_CHECK=("on" "off")
CF_DEFAULTS_ALWAYS_USE_HTTPS=("on" "off")
CF_DEFAULTS_MIN_TLS_VERSION=("1.0" "1.1" "1.2" "1.3")

# ==================================================
# -- pre_flight_check - Check for .cloudflare credentials
# ==================================================
function pre_flight_check () {
    if [[ -n $API_TOKEN ]]; then
        _running "Found \$API_TOKEN via CLI using for authentication/."          
    elif [[ -n $API_ACCOUNT ]]; then
        _running "Found \$API_ACCOUNT via CLI using as authentication."                
        if [[ -n $API_APIKEY ]]; then
            _running "Found \$API_APIKEY via CLI using as authentication."                        
        else
            _error "Found API Account via CLI, but no API Key found, use -ak...exiting"
            exit 1
        fi
    elif [[ -f "$HOME/.cloudflare" ]]; then
            _debug "Found .cloudflare file."
            # shellcheck source=$HOME/.cloudflare
            source "$HOME/.cloudflare"
            
            # If $CF_SPC_ACCOUNT and $CF_SPC_KEY are set, use them.
            if [[ $CF_SPC_TOKEN ]]; then
                _debug "Found \$CF_SPC_TOKEN in \$HOME/.cloudflare"
                API_TOKEN=$CF_SPC_TOKEN
            elif [[ $CF_SPC_ACCOUNT && $CF_SPC_KEY ]]; then
                _debug "Found \$CF_SPC_ACCOUNT and \$CF_SPC_KEY in \$HOME/.cloudflare"
                API_ACCOUNT=$CF_SPC_ACCOUNT
                API_APIKEY=$CF_SPC_KEY
            elif [[ $CF_ACCOUNT && $CF_KEY ]]; then
                _debug "Found \$CF_ACCOUNT and \$CF_KEY in \$HOME/.cloudflare"
                API_ACCOUNT=$CF_ACCOUNT
                API_APIKEY=$CF_KEY
            elif [[ $CF_ACCOUNT && $CF_TOKEN ]]; then
                _debug "Found \$CF_ACCOUNT and \$CF_TOKEN in \$HOME/.cloudflare"
                API_ACCOUNT=$CF_ACCOUNT
                API_APIKEY=$CF_TOKEN
            else
                _error "No \$CF_SPC_TOKEN or \$CF_KEY missing..exiting"            
                exit 1
            fi 
    else
        _error "Can't find \$HOME/.cloudflare, and no CLI options provided."
    fi

    # -- Required apps
    for app in "${REQUIRED_APPS[@]}"; do
        if ! command -v $app &> /dev/null; then
            _error "$app could not be found, please install it."
            exit 1
        fi
    done
}

# ==================================================
# -- _cf_api <$METHOD> <$API_PATH> <${CURL_HEADERS[@]}>
# -- returns $CURL_EXIT_CODE and $API_OUTPUT
# ==================================================
function _cf_api () {
    # -- Run cf_api with tokens
    _debug "function:${FUNCNAME[0]}"
    _debug "Running _cf_api() with ${*}"

    local PROCESS_PARAMS="1"
    local METHOD="${1^^}"
    shift
    local API_PATH="$1"
    shift
    local CURL_OUTPUT
    declare -a CURL_OPTS
    CURL_OPTS=()
    CURL_OUTPUT=$(mktemp)

    _debug "METHOD: $METHOD API_PATH: $API_PATH CURL_OUTPUT: $CURL_OUTPUT"

    if [[ -n $API_TOKEN ]]; then
        _debug "Running cf_api with Cloudflare Token"
        CURL_HEADERS=("-H" "Authorization: Bearer ${API_TOKEN}")
        _debug "Using \$API_TOKEN as token. \$CURL_HEADERS: ${CURL_HEADERS[*]}"                
    elif [[ -n $API_ACCOUNT ]]; then        
        _debug "Running cf_api with Cloudflare API Key"
        CURL_HEADERS=("-H" "X-Auth-Key: ${API_APIKEY}" -H "X-Auth-Email: ${API_ACCOUNT}")
        _debug "Using \$API_APIKEY as token. \$CURL_HEADERS: ${CURL_HEADERS[*]}"        
    else
        _error "No API Token or API Key found...major error...exiting"
        exit 1
    fi

    # -- Check method and apply form type
    if [[ $METHOD = "POST" ]]; then
        _debug "Setting form type to form-data"
        CURL_OPTS+=(-H "Content-Type: multipart/form-data")
        FORMTYPE="form"
    elif [[ $METHOD == "POST-JSON" ]]; then
        _debug "Setting form type to form-data and skipping processing parameters"
        CURL_OPTS+=(-H "Content-Type: application/json")
        METHOD="POST"
        FORMTYPE="data"
        PROCESS_PARAMS="1"
    elif [[ $METHOD = "PATCH" ]]; then
        _debug "Setting form type to form-data"
        CURL_OPTS+=(-H "Content-Type: application/json")
        FORMTYPE="data"        
        # -- Pass JSON via CURL_OPTS  
    else
        CURL_OPTS+=(--get)
    fi

    # -- Process parameters
    if [[ $PROCESS_PARAMS == "1" ]]; then
        while [ -n "$1" ]; do
            if [ ."$1" = .-- ]; then
                shift
                _debug "Parameters: ${*}"
                break
            else
                CURL_OPTS+=(--"$FORMTYPE" "$1")
            fi
            shift
        done
    else
        _debug "Skipping processing parameters"
    fi
	
    _debug "Running curl -s -w "%{http_code}" --request "${METHOD}" --url "${API_URL}${API_PATH}" "${CURL_HEADERS[*]} ${CURL_OPTS[*]}" "${EXTRA[@]}""
    [[ $DEBUG == "1" ]] && set -x
    CURL_EXIT_CODE=$(curl -s -w "%{http_code}" --request "$METHOD" \
        --url "${API_URL}${API_PATH}" \
        "${CURL_HEADERS[@]}" \
        "${CURL_OPTS[@]}" \
        --output "$CURL_OUTPUT" "${EXTRA[@]}")
    
    [[ $DEBUG == "1" ]] && set +x
    API_OUTPUT=$(<"$CURL_OUTPUT")
    _debug_json "$API_OUTPUT"
    rm $CURL_OUTPUT 

		
	if [[ $CURL_EXIT_CODE == "200" ]]; then
        _debug "=============== SUCCESS ==============="
	    _debug "CURL_EXIT_CODE: $CURL_EXIT_CODE"
        _debug "API_OUTPUT: $API_OUTPUT"
        echo "$API_OUTPUT"
	else
        _debug "=============== FAIL ==============="
        _debug "CF_ENDPOINT: $API_PATH CURL_EXIT_CODE: $CURL_EXIT_CODE"
        _debug "API_OUTPUT: $API_OUTPUT"
        echo "$API_OUTPUT"
        return 1
    fi
}

# ==================================================
# -- _cf_get_settings $CF_ZONEID
# ==================================================
function _cf_get_settings () {
	local CF_ZONE_ID=$1 SETTING_VALUE
	_debug "function:${FUNCNAME[0]}"
	_debug "Running _cf_get_settings() with ${*}"

    # -- Get Zone Settings
    for SETTING in "${!CF_SETTINGS[@]}"; do
        API_OUTPUT=$(_cf_api "GET" "/client/v4/zones/${CF_ZONE_ID}/settings/${SETTING}")
        _debug "API_OUTPUT: $API_OUTPUT CURL_EXIT_CODE: $CURL_EXIT_CODE"
        SETTING_VALUE=$(echo $API_OUTPUT | jq -r '.result.value')
        if [[ $SETTING == "challenge_ttl" ]]; then
            SETTING_VALUE=$(_convert_seconds $SETTING_VALUE)
        else
            SETTING_VALUE=$(echo $API_OUTPUT | jq -r '.result.value')
        fi
        echo "${CF_SETTINGS[$SETTING]}: $SETTING_VALUE"
    done
}

# ==================================================
# -- _cf_set_settings $CF_ZONEID $SETTING $VALUE
# ==================================================
_cf_set_settings () {
	local CF_ZONE_ID=$1 SETTING=$2 VALUE=$3
	_debug "function:${FUNCNAME[0]}"
	_debug "Running _cf_set_settings() with ${*}"
	
	_running "Setting $SETTING to $VALUE"
	_cf_api "PATCH" "/client/v4/zones/${CF_ZONE_ID}/settings/${SETTING}" "$(jq -n --arg value "$VALUE" '{"value": $value}')"
	if [[ $CURL_EXIT_CODE == "200" ]]; then
		_success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
		echo "Completed setting $SETTING to $VALUE successfully"
		exit 0
	else		
		exit 1
	fi
}

# ==================================================
# -- _cf_check_setting $SETTING
# ==================================================
function _cf_check_setting () {
    local SETTING=${1}
    _debug "function:${FUNCNAME[0]}"
    _debug "Checking $SETTING"
    if [[ " ${!CF_SETTINGS[*]} " =~ " ${SETTING} " ]]; then
        _debug "$SETTING is in the list of allowed settings"
        return 0
    else
        _error "$SETTING is not in the list of allowed settings"        
        _error "Allowed settings are: ${!CF_SETTINGS[*]}"        
        return 1
    fi

}

# ==================================================
# -- _cf_check_setting_value $SETTING $VALUE
# ==================================================
function _cf_check_setting_value () {
    # -- Array for each $SETTING and $VALUE is called $CF_SETTINGS_VALUES
    local SETTING=${1^^}
    local VALUE=$2
    _debug "function:${FUNCNAME[0]}"
    _debug "Checking $SETTING with value $VALUE"
    local CF_SETTINGS_VALUES
    # Load up CF_SETTINGS_{SETTING} array into $CF_SETTINGS_VALUES
    eval "CF_SETTINGS_VALUES=(\"\${CF_DEFAULTS_${SETTING}[@]}\")"
    _debug "Allowed values for $SETTING are: ${CF_SETTINGS_VALUES[*]}"
    

    # -- Check if $VALUE is in $CF_SETTINGS_VALUES
    if [[ " ${CF_SETTINGS_VALUES[*]} " =~ " ${VALUE} " ]]; then
        _debug "Value $VALUE is in $SETTING"
        return 0
    else
        _error "Value $VALUE is not in $SETTING"
        _error "Allowed values for $SETTING are: ${CF_SETTINGS_VALUES[*]}"
        return 1
    fi
}

# ==================================================
# -- _cf_settings_values $SETTING
# ==================================================
function _cf_settings_values () {
    local SETTING=${1^^}
    _debug "function:${FUNCNAME[0]}"
    _debug "Getting values for $SETTING"
    local CF_SETTINGS_VALUES
    # Load up CF_SETTINGS_{SETTING} array into $CF_SETTINGS_VALUES
    eval "CF_SETTINGS_VALUES=(\"\${CF_DEFAULTS_${SETTING}[@]}\")"
    _debug "Allowed values for $SETTING are: ${CF_SETTINGS_VALUES[*]}"

    if [[ $SETTING == "CHALLENGE_TTL" ]]; then
        echo "Possible Values:"
        for SECONDS in "${CF_SETTINGS_VALUES[@]}"; do
            echo -e "\t$SECONDS - $(_convert_seconds $SECONDS)"
        done            
    else
        echo "Possible Values: ${CF_SETTINGS_VALUES[*]}"
    fi   
}


# ==================================================
# -- _get_zone_id $DOMAIN
# ==================================================
function _get_zone_id () {
    _debug "function:${FUNCNAME[0]}"
    local DOMAIN=$1 API_OUTPUT QUIET=${2:-0}
    _debug "Running _get_zone_id() with ${*}"    
    local API_OUTPUT=$(_cf_api GET /client/v4/zones?name=${DOMAIN})

    if [[ $? == "0" ]]; then        
        CF_ZONE_ID=$(echo $API_OUTPUT | jq -r '.result[0].id' )
        _debug "${FUNCNAME[0]} - CF_ZONE_ID: $CF_ZONE_ID"
        if [[ $CF_ZONE_ID == "null" ]]; then
            _error "Couldn't get ZoneID, using -z to provide ZoneID or give access read:zone access to your token" >&2
            return 1
        else
            echo "$CF_ZONE_ID"
            return 0
        fi
    else
        _error "Couldn't get ZoneID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token" >&2
        _debug "API_OUTPUT: $API_OUTPUT"
        _debug "CURL_EXIT_CODE: $CURL_EXIT_CODE"
        return 1
    fi
}

# ==================================================
# -- _convert_seconds $SECONDS
# -- returns $HUMAN_TIME
# ==================================================
function _convert_seconds () {
    local T=$1
    local D=$((T/60/60/24))
    local H=$((T/60/60%24))
    local M=$((T/60%60))
    local S=$((T%60))
    local HUMAN_TIME

    if [ "$D" -gt 0 ]; then
        HUMAN_TIME="${D}d ${H}h ${M}m ${S}s"
    elif [ "$H" -gt 0 ]; then
        HUMAN_TIME="${H}h ${M}m ${S}s"
    elif [ "$M" -gt 0 ]; then
        HUMAN_TIME="${M}m ${S}s"
    else
        HUMAN_TIME="${S}s"
    fi

    echo "$HUMAN_TIME"
}

# ==================================================
# -- _cf_create_filter $ZONE_ID $EXPRESSION
# ==================================================
_cf_create_filter () {
    local ZONE_ID=$1
    _debug "function:${FUNCNAME[0]}"
    _running "Creating filter for $ZONE_ID"
    if [[ $DRYRUN == "1" ]]; then
        echo "DRYRUN: Would have created filter for $ZONE_ID"
    else
        _cf_api "POST" "/client/v4/zones/${ZONE_ID}/filters" "$(jq -n --arg expression "$EXPRESSION" '{"expression": $expression}')"
        if [[ $CURL_EXIT_CODE == "200" ]]; then
            _success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
            echo "Created filter for $ZONE_ID successfully"
        else
            _error "Error creating filter for $ZONE_ID"
            exit 1
        fi
    fi
}

# ==================================================
# --_cf_create_rule $ZONE_ID $FILTER_ID $ACTION $PRIORITY $DESCRIPTION
# ==================================================
_cf_create_rule () {
	local ZONE_ID=$1 FILTER_ID=$2 ACTION=$3 PRIORITY=$4 DESCRIPTION=$5

	echo " - Creating Rule with ID:$ZONE_ID - FILTER_ID:$FILTER_ID - ACTION:$ACTION PRIORITY:$PRIORITY - DESCRIPTION:$DESCRIPTION"    
    if [[ $DRYRUN == "1" ]]; then
        echo "DRYRUN: Would have created rule with ID:$ZONE_ID - FILTER_ID:$FILTER_ID - ACTION:$ACTION PRIORITY:$PRIORITY - DESCRIPTION:$DESCRIPTION"
    else
        _debug "Creating Rule with ID:$ZONE_ID - FILTER_ID:$FILTER_ID - ACTION:$ACTION PRIORITY:$PRIORITY - DESCRIPTION:$DESCRIPTION"
        _cf_api "POST" "/client/v4/zones/${ZONE_ID}/firewall/rules" \
        "$(jq -n --arg filter "$FILTER_ID" --arg action "$ACTION" --arg priority "$PRIORITY" --arg description "$DESCRIPTION" '{"filter": {"id": $filter}, "action": $action, "priority": $priority, "description": $description}')"

        # -- Check if the rule was created
        if [[ $CURL_EXIT_CODE == "200" ]]; then
            _success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
            echo "Created rule with ID:$ZONE_ID - FILTER_ID:$FILTER_ID - ACTION:$ACTION PRIORITY:$PRIORITY - DESCRIPTION:$DESCRIPTION"
        else
            _error "Error creating rule with ID:$ZONE_ID - FILTER_ID:$FILTER_ID - ACTION:$ACTION PRIORITY:$PRIORITY - DESCRIPTION:$DESCRIPTION"
            exit 1
        fi
	fi
}

# ==================================================
# -- _apply_profile $ZONE_ID $PROFILE_NAME
# ==================================================
function _apply_profile () {
    local ZONE_ID=$1 PROFILE_NAME=$2
    _debug "function:${FUNCNAME[0]}"
    _running "Applying profile $PROFILE_NAME"

    # -- Check if profile exists under profiles/$PROFILE_NAME
    if [[ -f "profiles/$PROFILE_NAME" ]]; then
        _debug "Found profile $PROFILE_NAME"
        # shellcheck source=profiles/block-xml-rpc
        echo "Not implemented yet"
        return 1
    else
        _error "Profile $PROFILE_NAME not found"
        exit 1
    fi
    
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
        echo "Created profile $PROFILE_NAME successfully"
        exit 0
    else
        _error "Error creating profile $PROFILE_NAME"
        exit 1
    fi
}

# ==================================================
# -- _get_domain_account_id $DOMAIN
# ==================================================
function _get_domain_account_id () {
    DFUNC="function:${FUNCNAME[0]}"
    _debug "$DFUNC: Getting Account ID for $DOMAIN"
    local DOMAIN=$1

    _running "Getting Account ID for $DOMAIN"
    _debug "$DFUNC: Running _cf_api GET /client/v4/zones?name=${DOMAIN}"
    API_OUTPUT=$(_cf_api "GET" "/client/v4/zones?name=${DOMAIN}")
    _debug "$DFUNC: API_OUTPUT: $API_OUTPUT"
    CF_API_EXIT_CODE="$?"

    if [[ $CF_API_EXIT_CODE == "0" ]]; then
        ACCOUNT_ID=$(echo $API_OUTPUT | jq -r '.result[0].account.id' )
        _debug "$DFUNC: ACCOUNT_ID: $ACCOUNT_ID"
        if [[ $ACCOUNT_ID == "null" ]]; then
            _error "$DFUNC: Couldn't get Account ID, using -a to provide Account ID or give access read:account access to your token" >&2
            return 1
        else            
            return 0
        fi
    else
        _error "$DFUNC: Couldn't get Account ID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token" >&2
        _debug "$DFUNC: API_OUTPUT: $API_OUTPUT"
        _debug "$DFUNC: CURL_EXIT_CODE: $CURL_EXIT_CODE"
        return 1
    fi
}


