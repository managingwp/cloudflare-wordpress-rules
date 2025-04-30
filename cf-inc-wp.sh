#!/usr/bin/env bash
# =================================================================================================
# cf-api-wp v0.1.0
# =================================================================================================

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
        
        CF_CREATE_FILTER_ID="$(cf_create_filter_json "$ZONE_ID" "$FILTER_DATA")"
        CF_CREATE_FILTER_ID_EXIT="$?"
        if [[ $CF_CREATE_FILTER_ID_EXIT -ne 0 ]]; then
            _error "Failed to create filter for $description"
            continue
        fi

        # Create rule using filter ID
        CF_CREATE_RULE_ID=$(CF_CREATE_RULE "$ZONE_ID" "$CF_CREATE_FILTER_ID" "$action" "$priority" "$description")
        CF_CREATE_RULE_ID_EXIT="$?"
        if [[ $CF_CREATE_RULE_ID_EXIT -ne 0 ]]; then
            _error "Failed to create rule"
            echo "$CF_CREATE_RULE_ID"
            continue
        fi

        _success "Created rule: $description"
    done
}
# =====================================
# -- cf_update_rules $DOMAIN_NAME $ZONE_ID $PROFILE_NAME
# -- Update rules based on a profile
# =====================================
cf_update_rules () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local PROFILE_NAME=$3
    local OBJECT="${DOMAIN_NAME}/${ZONE_ID}"

    _running2 "Updating rules on $OBJECT"

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
        cf_update_rules_profile "$ZONE_ID" "$PROFILE_FILE"
    fi
}



# =====================================
# -- cf_update_rules_profile $ZONE_ID $RULES_FILE 
# -- Update rules from a JSON file
# =====================================
function cf_update_rules_profile () {
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

        _running3 "Verifying rule: $description"
        # Check if rule already exists
        existing_rule=$(cf_list_rules "$ZONE_ID" | jq -r --arg desc "$description" '.result[] | select(.description == $desc)')
        if [[ -n $existing_rule ]]; then
            _success "Rule already exists: $description"
            continue
        else
            _error "Rule not found: $description"
        fi
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