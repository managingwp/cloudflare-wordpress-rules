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
            echo "Not implementing yet"
            continue
        else
            _error "Rule not found: $description"
        fi
    done
}

# =====================================
# -- cf_upgrade_rules_default $DOMAIN_NAME $ZONE_ID $PROFILE_NAME
# -- Upgrade rules based on a profile
# =====================================
function cf_upgrade_rules_default () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local PROFILE_NAME=$3
    local OBJECT="${DOMAIN_NAME}/${ZONE_ID}"
    local PROFILE_FILE="$PROFILE_DIR/$PROFILE_NAME.json"

    _running2 "Upgrading rules on $OBJECT"

    # -- Check if profile dir exists
    [[ ! -d $PROFILE_DIR ]] && _error "$PROFILE_DIR doesn't exist, failing" && exit 1

    # -- Check if profile exists    
    [[ ! -f $PROFILE_FILE ]] && _error "PROFILE_FILE doesn't exist, failing" && exit 1
    _running2 "Profile file found: $PROFILE_FILE upgrading rules."

    # -- Get existing rules
    local EXISTING_RULES
    # Go through rules and get the rule ID, and description separated by a comma
    EXISTING_RULES="$(cf_list_rules "$ZONE_ID")"    
    if [[ -z $EXISTING_RULES ]]; then
        _error "No existing rules found on $DOMAIN"
        return 1
    fi
    RULE_IDS=$(echo "$EXISTING_RULES" | jq -r '.result[] | .id')
    # -- Go through each rule can check if it can be updated
    for RULE_ID in $RULE_IDS; do
        # -- Get Description from $EXISTING_RULES
        DESCRIPTION=$(echo "$EXISTING_RULES" | jq -r --arg RULE_ID "$RULE_ID" '.result[] | select(.id == $RULE_ID) | .description')
        _running3 "Processing: $DESCRIPTION"
        
        # -- Take the first part of the description and check if it exists in the profile, should be R1V###        
        RULE_PREFIX=$(echo "$DESCRIPTION" | cut -d' ' -f1)
        _debug "Rule prefix: $RULE_PREFIX"

        # Parse rule prefix format: R#V### (example: R1V201)
        # Rule format validation
        if [[ "$RULE_PREFIX" =~ ^R([0-9]+)V([0-9]{3})$ ]]; then
            # Extract using bash regex capture groups
            RULE_NUMBER="${BASH_REMATCH[1]}"
            RULE_VERSION="${BASH_REMATCH[2]}"
            _success "Rule Number: $RULE_NUMBER Version: $RULE_VERSION"
        else
            _error "Invalid rule prefix format: '$RULE_PREFIX' - expected format R#V### (e.g., R1V201)"
            continue
        fi

        # -- Check if rule exists in the profile, based on the rule number.
        # -- Get the rule number from the profile
        PROFILE_RULE_NUMBER=$(jq -r --arg RULE_NUMBER "$RULE_NUMBER" '.rules[] | select(.rule_number == $RULE_NUMBER) | .rule_id' "$PROFILE_FILE")
        if [[ -z $PROFILE_RULE_NUMBER ]]; then
            _error "Rule $RULE_NUMBER not found in profile $PROFILE_NAME"
            continue
        fi
        _success "Rule $RULE_NUMBER found in profile $PROFILE_NAME"
        
        # -- Get the rule version from the profile, based on the rule number.
        PROFILE_RULE_VERSION=$(jq -r --arg RULE_NUMBER "$RULE_NUMBER" '.rules[] | select(.rule_number == $RULE_NUMBER) | .rule_version' "$PROFILE_FILE")
        if [[ -z $PROFILE_RULE_VERSION ]]; then
            _error "Rule $RULE_NUMBER version not found in profile $PROFILE_NAME"
            continue
        fi
        _success "Rule $RULE_NUMBER version $PROFILE_RULE_VERSION found in profile $PROFILE_NAME"
        # -- Check if the rule version is different from the existing rule version
        if [[ "$RULE_VERSION" != "$PROFILE_RULE_VERSION" ]]; then
            _warning "Rule version $RULE_VERSION is different from profile version $PROFILE_RULE_VERSION, updating rule"            
            # -- Delete the existing rule
            cf_update_rule_profile "$ZONE_ID" "$RULE_ID" "$RULE_NUMBER" "$PROFILE"            
        else
            _success "Rule version $RULE_VERSION is the same as profile version $PROFILE_RULE_VERSION"
        fi
    done
}

# =====================================
# -- cf_update_rule_profile $ZONE_ID $RULE_ID $RULE_NUMBER $PROFILE_NAME
# -- Update a rule based on a profile
# =====================================
function cf_update_rule_profile () {
    local ZONE_ID=$1
    local RULE_ID=$2
    local RULE_NUMBER=$3
    local PROFILE_NAME=$4    

    _running2 "Updating RULE_ID:$RULE_ID on ZONE_ID:$ZONE_ID using PROFILE_NAME:$PROFILE_NAME and RULE_NUMBER:$RULE_NUMBER"
    local PROFILE_FILE="$PROFILE_DIR/$PROFILE_NAME.json"

    # -- Update Description
    local PROFILE_DESCRIPTION
    PROFILE_DESCRIPTION=$(cat $PROFILE_FILE | jq -r --arg RULE_NUMBER "$RULE_NUMBER" '.rules[] | select(.rule_number == $RULE_NUMBER) | .description')
    _debug "Profile description: $PROFILE_DESCRIPTION"
    [[ -z $PROFILE_DESCRIPTION ]] && _error "Description not found for rule $RULE_NUMBER in profile $PROFILE_NAME" && return 1
    _running3 "Description found for rule $RULE_NUMBER in profile $PROFILE_NAME: $PROFILE_DESCRIPTION"

    # -- Update Action
    local PROFILE_ACTION
    PROFILE_ACTION=$(cat $PROFILE_FILE | jq -r --arg RULE_NUMBER "$RULE_NUMBER" '.rules[] | select(.rule_number == $RULE_NUMBER) | .action')
    [[ -z $PROFILE_ACTION ]] && _error "Action not found for rule $RULE_NUMBER in profile $PROFILE_NAME" && return 1
    _running3 "Action found for rule $RULE_NUMBER in profile $PROFILE_NAME: $PROFILE_ACTION"
    # -- Update Priority
    local PROFILE_PRIORITY
    PROFILE_PRIORITY=$(cat $PROFILE_FILE | jq -r --arg RULE_NUMBER "$RULE_NUMBER" '.rules[] | select(.rule_number == $RULE_NUMBER) | .priority')
    [[ -z $PROFILE_PRIORITY ]] && _error "Priority not found for rule $RULE_NUMBER in profile $PROFILE_NAME" && return 1
    _running3 "Priority found for rule $RULE_NUMBER in profile $PROFILE_NAME: $PROFILE_PRIORITY"
    # -- Update Expression
    local PROFILE_EXPRESSION
    PROFILE_EXPRESSION=$(cat $PROFILE_FILE | jq -r --arg RULE_NUMBER "$RULE_NUMBER" '.rules[] | select(.rule_number == $RULE_NUMBER) | .expression')
    [[ -z $PROFILE_EXPRESSION ]] && _error "Expression not found for rule $RULE_NUMBER in profile $PROFILE_NAME" && return 1
    _running3 "Expression found for rule $RULE_NUMBER in profile $PROFILE_NAME: $PROFILE_EXPRESSION"
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