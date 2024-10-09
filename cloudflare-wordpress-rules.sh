#!/usr/bin/env bash
# ==================================================
# -- Variables
# ==================================================
SCRIPT_NAME="cloudflare-wordpress-rules"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
VERSION=$(cat "${SCRIPT_DIR}/VERSION")
API_URL="https://api.cloudflare.com"
DEBUG="0"
DRYRUN="0"
REQUIRED_APPS=("jq" "column")
PROFILE_DIR="${SCRIPT_DIR}/profiles"


# ==================================================
# -- Libraries
# ==================================================
source "${SCRIPT_DIR}/lib/cloudflare-lib.sh"
source "${SCRIPT_DIR}/lib/cloudflare-lib-old.sh"
source "${SCRIPT_DIR}/lib/core.sh"


# -- usage
usage () {
	echo "Usage: $SCRIPT_NAME (-d|-dr) <command>"
	echo ""
	echo " Options"
	echo "   -d                         - Debug mode"
	echo "   -dr                        - Dry run, don't send to Cloudflare"
	echo ""
	echo " Commands"
	echo "   create-rules <domain> <profile>           - Create default rules for domain"
	echo "                                               default  - Based on https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/cloudflare-protect-wordpress.md"
	echo ""
	echo "   get-rules <domain>                        - Get rules"
	echo "   delete-rule <id>                          - Delete rule"
	echo "   delete-all-rules <domain>                 - Delete all rules"
	echo ""
	echo "   get-filters <id>                          - Get Filters"
	echo "   delete-filter <id>                        - Delete rule ID on domain"	
	echo "   get-filter-id <id>                        - Get Filter <id>"
	echo ""	
	echo "   set-settings <domain> <setting> <value>   - Set security settings on domain"
	echo "         security_level"
	echo "         challenge_ttl"
	echo "         browser_integrity_check"
	echo "         always_use_https"
	echo ""
	echo "   get-settings <domain>                     - Get security settings on domain"
	echo ""
	echo "   list-profiles                              - List profiles"
	echo ""
	echo ""
	echo "Examples"
	echo "   $SCRIPT_NAME delete-filter domain.com 32341983412384bv213v"
	echo "   $SCRIPT_NAME create-rules domain.com"
	echo ""
	echo "Cloudflare API Credentials should be placed in \$HOME/.cloudflare"
	echo ""
	echo "Version: $VERSION"
}

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
# -- CF_PROTECT_WP $CF_ZONE_ID
# ==================================================
CF_PROTECT_WP () {
	local CF_ZONE_ID=$1 CF_CREATE_FILTER_ID CF_CREATE_RULE
	# -- Block xmlrpc.php - Priority 1
	_creating "Creating Filter for - Block xml-rpc.php rule - P1"
	CF_CREATE_FILTER_ID=$(_cf_create_filter $CF_ZONE_ID '(http.request.uri.path eq "/wp-content/uploads/wp-activity-log/non_mirrored_logs.json") or (http.request.uri.path eq "/xmlrpc.php")')	
	if [[ $? == "1" ]]; then 
		_error "Failed to create filter."
		_error "$CF_CREATE_FILTER_ID"
		return 1
	fi
	
	CF_CREATE_RULE=$(_cf_create_rule $CF_ZONE_ID "$CF_CREATE_FILTER_ID" "block" "1" "Block URI Query, URL, User Agents, and IPs (Block) P1")
	if [[ $? == "1" ]]; then 
		_error "Failed to create rule."
		_error "$CF_CREATE_RULE"
		return 1
	fi
	_creating "Creating Rule - Block xml-rpc.php rule - P1"
	_separator

	# -- Allow URI Query, URL, User Agents, and IPs (Allow) - Priority 2
	_creating "  Creating - Allow URI Query, URL, User Agents, and IPs (Allow) P2"
    BLOG_VAULT_IPS_A=("88.99.145.111
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
	CF_CREATE_FILTER $CF_ZONE_ID '(ip.src in { '"${BLOG_VAULT_IPS_B}"' }) or (ip.src in {'"${WP_UMBRELLA}"'}) or (http.user_agent contains \"wp-iphone\") or (http.user_agent contains \"wp-android\") or (http.request.uri.query contains \"bvVersion\")'
	if [[ $? == "0" ]]; then
		CF_CREATE_RULE $CF_ZONE_ID "$CF_CREATE_FILTER_ID" "allow" "2" "Allow URI Query, URL, User Agents, and IPs (Allow) P2"
	fi
	_separator

	# --  Managed Challenge /wp-admin (Managed Challenge) - Priority 3
	_creating "  Creating Managed Challenge /wp-admin (Managed Challenge) rule - P3"	
	CF_CREATE_FILTER $CF_ZONE_ID '(http.request.uri.path contains \"/wp-login.php\") or (http.request.uri.path contains \"/wp-admin/\" and http.request.uri.path ne \"/wp-admin/admin-ajax.php\" and not http.request.uri.path contains \"/wp-admin/js/password-strength-meter.min.js\")'
	if [[ $? == "0" ]]; then
		CF_CREATE_RULE $CF_ZONE_ID "$CF_CREATE_FILTER_ID" "managed_challenge" "3" "Managed Challenge /wp-admin (Managed Challenge) P3"
	fi
	_separator
	
	# --  Allow Good Bots and User Agent/URI/URL Query (Allow) - Priority 4
	_creating "  Allow Good Bots and User Agent/URI/URL Query (Allow) - P4"
	CF_CREATE_FILTER $CF_ZONE_ID '(cf.client.bot) or (http.user_agent contains \"Metorik API Client\") or (http.user_agent contains \"Wordfence Central API\") or (http.request.uri.query contains \"wc-api=wc_shipstation\") or (http.user_agent eq \"Better Uptime Bot\") or (http.user_agent eq \"ShortPixel\") or (http.user_agent contains \"WPUmbrella\") or (http.user_agent contains \"Encrypt validation server\")'
	if [[ $? == "0" ]]; then
		CF_CREATE_RULE $CF_ZONE_ID "$CF_CREATE_FILTER_ID" "allow" "4" "Allow Good Bots and User Agent/URI/URL Query (Allow) P4"
	fi
	_separator

	# -- Challenge Outside of GEO (JS Challenge)	
	_creating "  Challenge Outside of GEO (JS Challenge) - P5"
	CF_CREATE_FILTER $CF_ZONE_ID '(not ip.geoip.country in {\"CA\" \"US\"})'
	if [[ $? == "0" ]]; then
		CF_CREATE_RULE $CF_ZONE_ID "$CF_CREATE_FILTER_ID" "js_challenge" "5" "Challenge Outside of GEO (JS Challenge) P5"
	fi
	_separator

	_success "  Completed Protect WP profile"
}

# ==================================================
# ==================================================
# -- Main loop
# ==================================================
# ==================================================

# -- Parse options
    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -d|--debug)
        DEBUG="1"
        shift # past argument
        ;;
        -dr|--dryrun)
        DRYRUN="1"
        shift # past argument
        ;;
        *)    # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        ;;
    esac
    done
set -- "${POSITIONAL[@]}" # restore positional parameters

# -- Commands
_debug "ARGS: ${*}@"
DOMAIN=$2
CMD=$1
PROFILE=$3
ID=$3

# -- Dryrun
if [[ $DRYRUN = "1" ]]; then
	_error "Dryrun not implemented yet"
fi

# -- Check for .cloudflare credentials
pre_flight_check

# -- Show usage if no domain provided
if [[ -z $DOMAIN ]]; then
    usage
    _error "No domain provided"
    exit 1
fi

# -- Check $CMD
if [[ -z $CMD ]]; then
	usage
	_error "No command provided"
	exit 1
fi

# -- Check if domain is valid
CF_ZONE_ID=$(_get_zone_id $DOMAIN >&1)
EXIT_CODE=$?
_debug "main: CF_ZONE_ID: $CF_ZONE_ID EXIT_CODE: $EXIT_CODE"
if [[ $EXIT_CODE == "1" ]]; then
	exit 1
fi


# ================
# -- create-rules
# ================
if [[ $CMD == "create-rules" ]]; then
	_running "Running Create rules on $DOMAIN"
	if [[ -z $PROFILE ]]; then
		_running2 "Missing profile name, using default for rules"
		[[ $? == "1" ]] && exit 1
		CF_PROTECT_WP $CF_ZONE_ID # @ISSUE needs to be migrated
	else
		_running "Creating rules on $CF_ZONE_ID using profile $PROFILE"
		apply_profile $CF_ZONE_ID $PROFILE
	fi
# ================
# -- custom-rules
# ================
elif [[ $CMD == "custom-rules" ]]; then
	_running "Running custom-rules"
	cf_custom_rules $PROFILE
# ================
# -- get-rules
# ================
elif [[ $CMD == "get-rules" ]]; then
    _running "  Running Get rules"
    CF_GET_RULES $CF_ZONE_ID
# ================
# -- delete-rule
# ================
elif [[ $CMD == "delete-rule" ]]; then
    _running "  Running Delete rule"
    CF_DELETE_RULE ${3}
# =================
# -- delete-all-rules
# =================
elif [[ $CMD == "delete-all-rules" ]]; then
	_running "  Running Delete all rules"
	CF_DELETE_ALL_RULES $CF_ZONE_ID
# ================
# -- get-filters
# ================
elif [[ $CMD == "get-filters" ]]; then
	_running "  Running Get filters"
	CF_GET_FILTERS $CF_ZONE_ID
# ================
# -- get-filter-id
# ================
elif [[ $CMD == "get-filter-id" ]]; then
	FILTER_ID=$3
    _running "  Running Get filter ID $FILTER_ID"
    if [[ -z $FILTER_ID ]]; then
    	usage
    	_error "No rule ID provided"
    	exit 1
    else
    	CF_GET_FILTER_ID $FILTER_ID
    fi
# ================
# -- delete-filter
# ================
elif [[ $CMD == "delete-filter" ]]; then
	FILTER_ID=$3
	if [[ -z $FILTER_ID ]]; then
		usage
		_error "No rule ID provided"
		exit 1
	else
		_running "  Running Delete filter"
		CF_DELETE_FILTER $FILTER_ID
	fi
# ================
# -- set-settings
# ================
elif [[ $CMD == "set-settings" ]]; then
	CF_SETTING=$3
	CF_VALUE=$4
	[[ -z $CF_SETTING ]] && { usage_set_settings;_error "No setting provided";exit 1; }
	[[ -z $CF_VALUE ]] && { usage_set_settings;_error "No value provided";_cf_settings_values $CF_SETTING;exit 1; }

	# -- Check if valid setting using CF_SETTINGS array
	if ! _cf_check_setting $3; then
		_error "Invalid setting provided"
		exit 1
	fi

	if ! _cf_check_setting_value $3 $4; then
		_error "Invalid value provided"
		exit 1
	fi

	# -- Run set settings
	_running "  Running Set settings"
	_cf_set_settings $CF_ZONE_ID $3 $4
# ================
# -- get-settings
# ================
elif [[ $CMD == "get-settings" ]]; then	
	_running "  Running Get settings"
	_cf_get_settings $CF_ZONE_ID
else
	usage 
	_error "No command provided"
	exit 1

fi
