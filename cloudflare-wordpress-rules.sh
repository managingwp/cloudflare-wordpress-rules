#!/bin/bash
# =============================================================================
# A script to create Cloudflare WAF rules
# =============================================================================

# ==================================
# -- Variables
# ==================================
SCRIPT_NAME="cloudflare-wordpress-rules"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
VERSION=$(cat "${SCRIPT_DIR}/VERSION")
DEBUG="0"
DRYRUN="0"
QUIET="0"
PROFILE_DIR="${SCRIPT_DIR}/profiles"

# ==================================
# -- Include cf-inc.sh and cf-api-inc.sh
# ==================================
source "$SCRIPT_DIR/cf-inc.sh"
source "$SCRIPT_DIR/cf-inc-api.sh"

# ==================================
# -- usage
# ==================================
usage () {
	echo "Usage: $SCRIPT_NAME -d <domain> -c <command>"
	echo 
	echo " Commands"
	echo "   create-rules-v1                     - Create rules on domain using v1 rules"
	echo
	echo "   create-rules-profile <profile>      - Create rules on domain using profile"
	echo "   list-profiles                       - List profiles"
	echo
	echo "   list-rules                          - List rules"
	echo "   delete-rule <id>                    - Delete rule"
	echo "   delete-rules                        - Delete all rules"
	echo
	echo "   list-filters <id>                   - Get Filters"
	echo "   delete-filter <id>                  - Delete rule ID on domain"
	echo "   delete-filters                      - Delete all filters"
	echo 
	echo " Options"
	echo "   --debug                                  - Debug mode"
	echo "   -dr                                 - Dry run, don't send to Cloudflare"
	echo 
	echo " Profiles - See profiles directory for example."
	echo "   default                             - Default using v2 rules."
	echo 
	echo "Examples"
	echo "   $SCRIPT_NAME -d domain.com -c delete-filter 32341983412384bv213v"
	echo "   $SCRIPT_NAME -d domain.com -c create-rules"
	echo ""
	echo "Cloudflare API Credentials should be placed in \$HOME/.cloudflare"
	echo ""
	echo "Version: $VERSION"
}

# =====================================
# -- cf_profile_create $DOMAIN_NAME $ZONE_ID $PROFILE_NAME
# -- Create a set of rules based on a profile
# =====================================
cf_profile_create () {
	local DOMAIN_NAME=$1
	local ZONE_ID=$2
	local PROFILE_NAME=$3
	local OBJECT="${DOMAIN_NAME}/${ZONE_ID}"

	_running2 "Creating profile $PROFILE_NAME on $OBJECT"

	# -- Check if profile dir exists
	if [[ ! -d $PROFILE_DIR ]]; then
		_error "$PROFILE_DIR doesn't exist, failing"
		exit 1
	fi

	# -- Check if profile exists
	PROFILE_FILE="$PROFILE_DIR/$PROFILE_NAME.json"
	if [[ ! -f $PROFILE_FILE ]]; then
		_error "PROFILE_FILE doesn't exist, failing"
		exit 1
	else		
		_running2 "Profile file found: $PROFILE_FILE reating rules on $OBJECT"
		if ! jq empty "$PROFILE_FILE" 2>/dev/null; then
			_error "Invalid JSON in $PROFILE_FILE"
			return 1
		fi

		# -- Read JSON file
		cf_create_rules_profile $ZONE_ID $PROFILE_FILE
	fi
}

# =====================================
# -- cf_create_rules_profile $ZONE_ID $RULES_FILE
# -- Create rules from a JSON file
# =====================================
function cf_create_rules_profile () {
    local ZONE_ID=$1
    local RULES_FILE=$2

    if [[ ! -f "$RULES_FILE" ]]; then
        _error "Rules file not found: $RULES_FILE"
        return 1
    fi

    # Read each rule from JSON file
    jq -c '.rules[]' "$RULES_FILE" | while read -r rule; do
        # Extract and escape properties
        expression=$(echo "$rule" | jq -r '.expression' | sed 's/"/\\"/g')
        action=$(echo "$rule" | jq -r '.action')
        priority=$(echo "$rule" | jq -r '.priority')
        description=$(echo "$rule" | jq -r '.description')

        _debug "Expression being sent: $expression"
        
        # Create filter with JSON payload
        FILTER_DATA="{\"expression\":\"${expression}\"}"
        _debug "Filter payload: $FILTER_DATA"
        
        CF_CREATE_FILTER_ID=$(cf_create_filter_json "$ZONE_ID" "$FILTER_DATA")
        if [[ $? -ne 0 ]]; then
            _error "Failed to create filter for $description"
            continue
        fi

        # Create rule using filter ID
        CF_CREATE_RULE_ID=$(CF_CREATE_RULE "$ZONE_ID" "$CF_CREATE_FILTER_ID" "$action" "$priority" "$description")
        if [[ $? -ne 0 ]]; then
            _error "Failed to create rule"
            continue
        fi

        _success "Created rule: $description"
    done
}

# =====================================
# -- cf_list_profiles
# -- List profiles
# =====================================
cf_list_profiles () {
	local OUTPUT=""	
	# -- Check if profile dir exists
	if [[ ! -d $PROFILE_DIR ]]; then
		_error "$PROFILE_DIR doesn't exist, failing"
		exit 1
	fi

	# -- List profiles, each file has root json name and description
	i=1
	OUTPUT+="#\tFile\tName\tDescription\n"
	OUTPUT+="--\t----\t----\t-----------\n"
	for FILE in $PROFILE_DIR/*.json; do				
		PROFILE_FILE=$(basename $FILE)
		PROFILE_NAME=$(jq -r '.name' $FILE)
		PROFILE_DESC=$(jq -r '.description' $FILE)
		OUTPUT+="$i\t$PROFILE_FILE\t$PROFILE_NAME\t$PROFILE_DESC\n"
		i=$((i+1))
	done

	echo -e "$OUTPUT" | column -t -s $'\t'
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
	CF_CREATE_RULE_ID=$(CF_CREATE_RULE $ZONE_ID $CF_CREATE_FILTER_ID "js_challenge" "5" "Challenge Outside of GEO (JS Challenge)")
	[[ $? == "1" ]] && exit 1
	_success "Completed Challenge Outside of GEO (JS Challenge)"
    _separator

    _success "  Completed Protect WP profile"
}

# =============================================================================
# -- main
# =============================================================================

# -- Parse options
    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
		-d|--domain)
		DOMAIN="$2"
		shift # past argument
		shift # past variable
		;;
		-c|--command)
		CMD="$2"
		shift # past argument
		shift # past variable
		;;
        --debug)
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
PROFILE=$3
ID=$3

# -- pre-flight check
_debug "Pre-flight_check"
[[ $CMD != "test-token" ]] && _pre_flight_check "CF_"

# -- Dryrun
if [[ $DRYRUN = "1" ]]; then
    _error "Dryrun not implemented yet"
fi

# -- Check $CMD
if [[ -z $CMD ]]; then
    usage
    _error "No command provided"
    exit 1
fi

if [[ $CMD == "list-profiles" ]]; then
	_running2 "Listing profiles"
	cf_list_profiles
	exit 0
fi

# -- Show usage if no domain provided
if [[ -z $DOMAIN ]]; then
    usage
    _error "No domain provided"
    exit 1
else
    ZONE_ID=$(_cf_zone_id $DOMAIN)	
	if [[ -z $ZONE_ID ]]; then
		_error "No zone ID found for $DOMAIN"
		exit 1
	else
		_running2 "Zone ID found: $ZONE_ID"
	fi
fi

_running "Running $CMD on $DOMAIN with ID $ZONE_ID"
# =====================================
# -- create-rules-v1
# =====================================
if [[ $CMD == "create-rules-v1" ]]; then        
    CF_PROTECT_WP $ZONE_ID
# =====================================
# -- create-rules-profile
# =====================================
elif [[ $CMD == "create-rules-profile" ]]; then
	PROFILE=$1
	[[ $PROFILE == "" ]] && _error "No profile provided" && exit 1
    cf_profile_create $DOMAIN $ZONE_ID $PROFILE
# =====================================
# -- list-rules
# =====================================
elif [[ $CMD == "list-rules" ]]; then
    cf_list_rules_action $DOMAIN $ZONE_ID
# =====================================
# -- delete-rules
# =====================================
elif [[ $CMD == "delete-rules" ]]; then
    cf_delete_rules_action $DOMAIN $ZONE_ID
# =====================================
# -- delete-rule
# =====================================
elif [[ $CMD == "delete-rule" ]]; then
    RULE_ID=$1
	[[ $RULE_ID == "" ]] && _error "No rule ID provided" && exit 1
	cf_delete_rule_action $DOMAIN $ZONE_ID $RULE_ID
# =====================================
# -- list-filters
# =====================================
elif [[ $CMD == "list-filters" ]]; then
    cf_list_filters_action $DOMAIN $ZONE_ID
# =====================================
# -- get-filter
# =====================================
elif [[ $CMD == "get-filter" ]]; then
    FILTER_ID=$1
	_running2 "Getting filter ID $FILTER_ID"
    if [[ -z $FILTER_ID ]]; then
        usage
        _error "No filter ID provided"
        exit 1
    else
        CF_GET_FILTER $ZONE_ID $FILTER_ID
    fi
# =====================================
# -- delete-filter
# =====================================
elif [[ $CMD == "delete-filter" ]]; then
	FILTER_ID=$1
    [[ $FILTER_ID == "" ]] && _error "No filter ID provided" && exit 1
	cf_delete_filter_action $DOMAIN $ZONE_ID $FILTER_ID
# =====================================
# -- delete-filters
# =====================================
elif [[ $CMD == "delete-filters" ]]; then
	cf_delete_filters_action $DOMAIN $ZONE_ID
else
    usage
    _error "No command provided"
    exit 1
fi
