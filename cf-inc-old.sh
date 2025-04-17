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

# -- usage_set_settings
function usage_set_settings () {
	echo "Usage: $SCRIPT_NAME set-settings <domain> <setting> <value>"
	echo ""
	echo " Settings"
	# -- Loop through CF_SETTINGS array and print out key
	for i in "${!CF_SETTINGS[@]}"; do
		echo "   ${i}"
	done
	echo ""
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
# -- _cf_get_settings $CF_ZONEID
# ==================================================
function _cf_get_settings () {	
	_debug "function:${FUNCNAME[0]} - ${*}"
    local CF_ZONE_ID=$1
    local SETTING_VALUE

    # -- Get Zone Settings
    for SETTING in "${!CF_SETTINGS[@]}"; do
        cf_api "GET" "/client/v4/zones/${CF_ZONE_ID}/settings/${SETTING}"
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
    _debug "function:${FUNCNAME[0]} - ${*}"

	local CF_ZONE_ID=$1 SETTING=$2 VALUE=$3
	_debug "function:${FUNCNAME[0]}"
	_debug "Running _cf_set_settings() with ${*}"
	
	_running "Setting $SETTING to $VALUE"
    EXTRA=(-H "Content-Type: application/json" \
     --data 
    '{ "value": "'"$VALUE"'" }')        
	cf_api "PATCH" "/client/v4/zones/${CF_ZONE_ID}/settings/${SETTING}" "${EXTRA[@]}"
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