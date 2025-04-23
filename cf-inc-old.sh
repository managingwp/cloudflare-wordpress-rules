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

    # -- Get Zone Settings
    cf_api "GET" "/client/v4/zones/${CF_ZONE_ID}/settings"
    _debug "API_OUTPUT: $API_OUTPUT CURL_EXIT_CODE: $CURL_EXIT_CODE"

    # -- Process each setting we're interested in
    for SETTING in "${!CF_SETTINGS[@]}"; do
        _debug "Processing setting: $SETTING"
        # Extract the value for this specific setting ID from the results array
        SETTING_VALUE=$(echo "$API_OUTPUT" | jq -r --arg id "$SETTING" '.result[] | select(.id==$id) | .value')
        _debug "Setting value: $SETTING_VALUE"
        
        # If value is empty (setting not found), continue to next setting
        if [[ -z "$SETTING_VALUE" ]]; then
            _debug "Setting $SETTING not found in API response"
            continue
        fi
        
        # Apply special formatting for certain settings
        if [[ $SETTING == "challenge_ttl" ]]; then
            if [[ "$SETTING_VALUE" =~ ^[0-9]+$ ]]; then
                HUMAN_TIME=$(_convert_seconds "$SETTING_VALUE")
                SETTING_VALUE="$SETTING_VALUE ($HUMAN_TIME)"
            fi
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

# ================================
# -- CF_PROTECT_WP $ZONE_ID
# ================================
function CF_PROTECT_WP () {
	local ZONE_ID=$1
	# -- Block xmlrpc.php - Priority 1
	_running2 "Creating - Block xml-rpc.php rule on $DOMAIN - $ZONE_ID"
	CF_CREATE_FILTER_ID=$(CF_CREATE_FILTER $ZONE_ID 'http.request.uri.path eq \"/xmlrpc.php\"')
	[[ $? == "1" ]] && exit 1
	CF_CREATE_RULE_ID=$(CF_CREATE_RULE $ZONE_ID $CF_CREATE_FILTER_ID "block" "1" "Block xml-rpc.php")
	[[ $? == "1" ]] && exit 1
	_success "Completed Block xml-rpc.php rule - $CF_CREATE_RULE_ID"

	_separator

	# -- Allow URI Query, URL, User Agents, and IPs (Allow) - Priority 2
	_running2 "  Creating - Allow URI Query, URL, User Agents, and IPs (Allow)"
    BLOG_VAULT_IPS_A=(" 88.99.145.111
88.99.145.112
195.201.197.31
136.243.130.174
144.76.236.242
136.243.130.52
116.202.131.150
116.202.233.15
116.202.193.3
168.119.2.157
49.12.124.233
88.99.146.248
139.180.140.55
104.248.114.9
192.81.221.63
45.63.10.187
45.76.137.73
45.76.183.23
159.223.99.132
198.211.127.63
45.76.126.238
159.223.105.100
161.35.121.79
208.68.38.165
147.182.131.77
174.138.35.170
149.28.228.237
45.77.106.232
140.82.15.60
108.61.142.158
45.77.220.240
67.205.160.142
137.184.156.126
157.245.142.130
159.223.127.73
198.211.127.43
198.211.123.140
82.196.0.67
188.166.158.7
46.101.79.124
192.248.168.22
78.141.225.57
95.179.214.63
104.238.190.161
95.179.208.185
95.179.220.182
66.135.5.151
45.32.7.254
149.28.227.238
8.9.37.67
149.28.231.28
142.132.211.19
142.132.211.18
142.132.211.17
159.223.166.150
167.172.146.73
143.198.184.39
161.35.123.156
147.182.139.65
198.211.125.219
185.14.187.177
192.81.222.35
209.97.131.196
209.97.135.165
104.238.170.64
78.141.244.3
217.69.0.229
45.63.115.86
108.61.123.152
45.32.144.195
140.82.12.121
45.77.99.218
45.63.11.48
149.28.45.216
209.222.10.118")
	BLOG_VAULT_IPS_B=$(echo $BLOG_VAULT_IPS_A|tr "\n" " ")
    WP_UMBRELLA="141.95.192.2"
    echo '(ip.src in { '"${BLOG_VAULT_IPS_B}"' '"${WP_UMBRELLA}"'})'

	CF_CREATE_FILTER_ID=$(CF_CREATE_FILTER $ZONE_ID '(ip.src in { '"${BLOG_VAULT_IPS_B}"' }) or (ip.src in {'"${WP_UMBRELLA}"'})')
	[[ $? == "1" ]] && exit 1
	CF_CREATE_RULE_ID=$(CF_CREATE_RULE $ZONE_ID $CF_CREATE_FILTER_ID "allow" "2" "Allow URI Query, URL, User Agents, and IPs (Allow)")
	[[ $? == "1" ]] && exit 1
	_success "Completed  - Allow URI Query, URL, User Agents, and IPs (Allow)"
	_separator

	# --  Managed Challenge /wp-admin (Managed Challenge) - Priority 3
	_creating "  Creating Managed Challenge /wp-admin (Managed Challenge) rule"
	CF_CREATE_FILTER_ID=$(CF_CREATE_FILTER $ZONE_ID '(http.request.uri.path contains \"/wp-login.php\") or (http.request.uri.path contains \"/wp-admin/\" and http.request.uri.path ne \"/wp-admin/admin-ajax.php\" and not http.request.uri.path contains \"/wp-admin/js/password-strength-meter.min.js\")')
	[[ $? == "1" ]] && exit 1
	CF_CREATE_RULE_ID=$(CF_CREATE_RULE $ZONE_ID $CF_CREATE_FILTER_ID "managed_challenge" "3" "Managed Challenge /wp-admin (Managed Challenge)")
	[[ $? == "1" ]] && exit 1
	_success "Completed Managed Challenge /wp-admin (Managed Challenge)"
	_separator

	# --  Allow Good Bots and User Agent/URI/URL Query (Allow) - Priority 4
	_creating "  Allow Good Bots and User Agent/URI/URL Query (Allow)"
	CF_CREATE_FILTER_ID=$(CF_CREATE_FILTER $ZONE_ID '(cf.client.bot) or (http.user_agent contains \"Metorik API Client\") or (http.user_agent contains \"Wordfence Central API\") or (http.request.uri.query contains \"wc-api=wc_shipstation\") or (http.user_agent contains \"Better Uptime Bot\") or (http.user_agent contains \"ShortPixel\") or (http.user_agent contains \"WPUmbrella\")')
	[[ $? == "1" ]] && exit 1
	CF_CREATE_RULE_ID=$(CF_CREATE_RULE $ZONE_ID $CF_CREATE_FILTER_ID "allow" "4" "Allow Good Bots and User Agent/URI/URL Query (Allow)")
	[[ $? == "1" ]] && exit 1
	_success "Completed Allow Good Bots and User Agent/URI/URL Query (Allow)"
	_separator

    # -- Challenge Outside of GEO (JS Challenge)
    _creating "  Challenge Outside of GEO (JS Challenge)"
	CF_CREATE_FILTER_ID=$(CF_CREATE_FILTER $ZONE_ID '(not ip.geoip.country in {\"CA\" \"US\"})')
	[[ $? == "1" ]] && exit 1
	CF_CREATE_RULE_ID=$(CF_CREATE_RULE "$ZONE_ID" "$CF_CREATE_FILTER_ID" "js_challenge" "5" "Challenge Outside of GEO (JS Challenge)")
	[[ $? == "1" ]] && exit 1
	_success "Completed Challenge Outside of GEO (JS Challenge)"
    _separator

    _success "  Completed Protect WP profile"
}
