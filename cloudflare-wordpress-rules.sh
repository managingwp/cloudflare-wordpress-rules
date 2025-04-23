#!/usr/bin/env bash
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
source "$SCRIPT_DIR/cf-inc-old.sh"

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
	echo "   print-profile <profile>             - Print rules from profile"
	echo
	echo "   list-rules                          - List rules"
	echo "   delete-rule <id>                    - Delete rule"
	echo "   delete-rules                        - Delete all rules"
	echo
	echo "   list-filters <id>                   - Get Filters"
	echo "   delete-filter <id>                  - Delete rule ID on domain"
	echo "   delete-filters                      - Delete all filters"
	echo 
	echo "   set-settings <domain> <setting> <value>   - Set security settings on domain"
	echo "         security_level"
	echo "         challenge_ttl"
	echo "         browser_integrity_check"
	echo "         always_use_https"
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
		cf_create_rules_profile "$ZONE_ID" "$PROFILE_FILE"
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
        
        if ! cf_create_filter_json "$ZONE_ID" "$FILTER_DATA"; then
            _error "Failed to create filter for $description"
            continue
        fi

        # Create rule using filter ID
        #CF_CREATE_RULE_ID=$(CF_CREATE_RULE "$ZONE_ID" "$CF_CREATE_FILTER_ID" "$action" "$priority" "$description")
        if ! CF_CREATE_RULE "$ZONE_ID" "$CF_CREATE_FILTER_ID" "$action" "$priority" "$description"; then
            _error "Failed to create rule"
            echo "$CF_CREATE_RULE_ID"
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
	for FILE in "$PROFILE_DIR"/*.json; do
		_debug "Processing file: $FILE"		
		PROFILE_FILE=$(basename "$FILE")
		PROFILE_NAME=$(jq -r '.name' "$FILE")
		PROFILE_DESC=$(jq -r '.description' "$FILE")
		OUTPUT+="$i\t$PROFILE_FILE\t$PROFILE_NAME\t$PROFILE_DESC\n"
		i=$((i+1))
	done

	echo -e "$OUTPUT" | column -t -s $'\t'
}

# =====================================
# -- cf_print_profile $PROFILE_NAME
# -- Print rules from profile
# =====================================
function cf_print_profile () {
    PROFILE_NAME=$1
    PROFILE_FILE="$PROFILE_DIR/$PROFILE_NAME.json"
    if [[ ! -f $PROFILE_FILE ]]; then
        _error "Profile file not found: $PROFILE_FILE"
        return 1
    fi
    
    # Get rule count
    local RULE_COUNT
	RULE_COUNT=$(jq '.rules | length' "$PROFILE_FILE")
    _running2 "Found $RULE_COUNT rules in profile $PROFILE_NAME"
    
    # Loop through each rule
    for ((i=0; i<RULE_COUNT; i++)); do
        # Extract rule details
        local DESCRIPTION ACTION PRIORITY EXPRESSION
		DESCRIPTION=$(jq -r ".rules[$i].description" "$PROFILE_FILE")
		ACTION=$(jq -r ".rules[$i].action" "$PROFILE_FILE")        
		PRIORITY=$(jq -r ".rules[$i].priority" "$PROFILE_FILE")        
        # Extract and unescape expression
		EXPRESSION=$(jq -r ".rules[$i].expression" "$PROFILE_FILE" | sed 's/\\"/"/g')
        
        # Print rule details
        echo -e "\n${CYELLOW}Rule $((i+1)) - $DESCRIPTION (Priority: $PRIORITY, Action: $ACTION)${NC}"
        echo -e "${CGREEN}Expression:${NC}"
        echo "$EXPRESSION"
        echo -e "${CCYAN}$(printf '=%.0s' {1..80})${NC}"
    done
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
        # shellcheck disable=SC2034
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

# -- Show usage if no domain provided
if [[ -n $DOMAIN ]]; then
    ZONE_ID=$(_cf_zone_id "$DOMAIN")	
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
    CF_PROTECT_WP "$ZONE_ID"
# =====================================
# -- create-rules-profile
# =====================================
elif [[ $CMD == "create-rules-profile" ]]; then
	PROFILE=$1
	[[ $PROFILE == "" ]] && _error "No profile provided" && exit 1
    cf_profile_create "$DOMAIN" "$ZONE_ID" "$PROFILE"
# =====================================
# -- list-profiles
# =====================================
elif [[ $CMD == "list-profiles" ]]; then
	_running2 "Listing profiles"
	cf_list_profiles
	exit 0
# =====================================
# -- print-profile
# =====================================
elif [[ $CMD == "print-profile" ]]; then
	PROFILE=$1
	[[ $PROFILE == "" ]] && _error "No profile provided" && exit 1
	_running2 "Printing rules from profile $PROFILE"
	cf_print_profile "$PROFILE"
	exit 0
# =====================================
# -- list-rules
# =====================================
elif [[ $CMD == "list-rules" ]]; then
    cf_list_rules_action "$DOMAIN" "$ZONE_ID"
# =====================================
# -- delete-rules
# =====================================
elif [[ $CMD == "delete-rules" ]]; then
    cf_delete_rules_action "$DOMAIN" "$ZONE_ID"
# =====================================
# -- delete-rule
# =====================================
elif [[ $CMD == "delete-rule" ]]; then
    RULE_ID=$1
	[[ $RULE_ID == "" ]] && _error "No rule ID provided" && exit 1
	cf_delete_rule_action "$DOMAIN" "$ZONE_ID" "$RULE_ID"
# =====================================
# -- list-filters
# =====================================
elif [[ $CMD == "list-filters" ]]; then
    cf_list_filters_action "$DOMAIN" "$ZONE_ID"
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
        CF_GET_FILTER "$ZONE_ID" "$FILTER_ID"
    fi
# =====================================
# -- delete-filter
# =====================================
elif [[ $CMD == "delete-filter" ]]; then
	FILTER_ID=$1
    [[ $FILTER_ID == "" ]] && _error "No filter ID provided" && exit 1
	cf_delete_filter_action "$DOMAIN" "$ZONE_ID" "$FILTER_ID"
# =====================================
# -- delete-filters
# =====================================
elif [[ $CMD == "delete-filters" ]]; then
	cf_delete_filters_action "$DOMAIN" "$ZONE_ID"
# ================
# -- set-settings
# ================
elif [[ $CMD == "set-settings" ]]; then	# -- Run set settings
	_running "  Running Set settings"
	_cf_set_settings "$ZONE_ID" "$@"
# ================
# -- get-settings
# ================
elif [[ $CMD == "get-settings" ]]; then	
	_cf_get_settings "$ZONE_ID"
else
    usage
    _error "No command provided"
    exit 1
fi
