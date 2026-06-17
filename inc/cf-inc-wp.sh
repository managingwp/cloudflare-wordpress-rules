#!/usr/bin/env bash
# =================================================================================================
# cf-api-wp v0.2.0 — Rewritten for Rulesets API (Phase 4)
# =================================================================================================

# =============================================================================
# -- Internal Helpers
# =============================================================================

# =====================================
# -- _cf_ruleset_read_profile_rules $PROFILE_FILE
# -- Read rules from a profile file (v2 or v3) and output a JSON array
# -- suitable for the Rulesets API.
# -- v2 → v3 conversion: allow→skip, bypass→skip, drop priority, add enabled/logging
# -- Returns: JSON array via stdout
# =====================================
function _cf_ruleset_read_profile_rules () {
    local PROFILE_FILE=$1
    
    if [[ ! -f "$PROFILE_FILE" ]]; then
        _error "Profile file not found: $PROFILE_FILE"
        return 1
    fi
    
    local SCHEMA_VERSION
    SCHEMA_VERSION=$(jq -r '.version // 2' "$PROFILE_FILE")
    
    if [[ "$SCHEMA_VERSION" -ge 3 ]]; then
        # v3: keep expression, action, description, action_parameters
        # Strip internal tracking fields (enabled, logging, rule_number, rule_version)
        jq -c '[.rules[] | del(.rule_number, .rule_version, .enabled, .logging) | if .action_parameters == {} then del(.action_parameters) else . end]' "$PROFILE_FILE"
    else
        # v2: convert to v3 format
        # - allow → skip with action_parameters.ruleset = "current"
        # - bypass → skip with action_parameters.phases
        # - drop all other non-API fields
        _warning "v2 profile detected — converting action names (allow→skip) and removing non-API fields"
        jq -c '
            [
                .rules[] | {
                    description: .description,
                    expression: .expression,
                    action: (
                        if .action == "allow" then "skip"
                        elif .action == "bypass" then "skip"
                        else .action
                        end
                    )
                } + (
                    if .action == "allow" then { action_parameters: { "ruleset": "current" } }
                    elif .action == "bypass" then { action_parameters: { "phases": ["http_request_firewall_managed", "http_ratelimit", "http_request_firewall_custom"] } }
                    else {}
                    end
                )
            ]
        ' "$PROFILE_FILE"
    fi
}

# =============================================================================
# -- Profile Create (Rulesets API)
# =============================================================================

# =====================================
# -- cf_profile_create $DOMAIN_NAME $ZONE_ID $PROFILE_NAME
# -- Create a set of rules based on a profile using the Rulesets API.
# -- Supports both v2 and v3 profile formats (auto-converts v2).
# =====================================
cf_profile_create () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local PROFILE_NAME=$3
    local OBJECT="${DOMAIN_NAME}/${ZONE_ID}"

    _running2 "Creating profile $PROFILE_NAME on $OBJECT (Rulesets API)"

    # -- Check profile dir
    if [[ ! -d $PROFILE_DIR ]]; then
        _error "$PROFILE_DIR doesn't exist, failing"
        exit 1
    fi

    local PROFILE_FILE="$PROFILE_DIR/$PROFILE_NAME.json"
    if [[ ! -f $PROFILE_FILE ]]; then
        _error "Profile file not found: $PROFILE_FILE"
        exit 1
    fi

    # -- Validate JSON
    if ! jq empty "$PROFILE_FILE" 2>/dev/null; then
        _error "Invalid JSON in $PROFILE_FILE"
        return 1
    fi
    _running2 "Profile file found: $PROFILE_FILE"

    # -- Read and convert rules to Rulesets API format
    local RULES_JSON
    RULES_JSON=$(_cf_ruleset_read_profile_rules "$PROFILE_FILE")
    if [[ -z "$RULES_JSON" || "$RULES_JSON" == "null" ]]; then
        _error "Failed to read rules from profile $PROFILE_NAME"
        return 1
    fi

    # -- Apply rules via Rulesets API (get-or-create + replace-all)
    if cf_ruleset_apply_profile "$ZONE_ID" "$RULES_JSON"; then
        _success "Created profile $PROFILE_NAME on $OBJECT"
        return 0
    else
        _error "Failed to create profile $PROFILE_NAME on $OBJECT"
        return 1
    fi
}

# =====================================
# -- cf_create_rules_profile $ZONE_ID $RULES_FILE
# -- Create rules from a JSON file using the Rulesets API.
# -- Reads all rules from the file and applies them in a single PUT.
# =====================================
function cf_create_rules_profile () {
    local ZONE_ID=$1
    local RULES_FILE=$2

    if [[ ! -f "$RULES_FILE" ]]; then
        _error "Rules file not found: $RULES_FILE"
        return 1
    fi

    local RULES_JSON
    RULES_JSON=$(_cf_ruleset_read_profile_rules "$RULES_FILE")
    if [[ -z "$RULES_JSON" || "$RULES_JSON" == "null" ]]; then
        _error "Failed to read rules from $RULES_FILE"
        return 1
    fi

    cf_ruleset_apply_profile "$ZONE_ID" "$RULES_JSON"
}

# =============================================================================
# -- Profile Update (Rulesets API)
# =============================================================================

# =====================================
# -- cf_update_rules $DOMAIN_NAME $ZONE_ID $PROFILE_NAME
# -- Update rules on a zone by replacing all rules with those from the profile.
# -- Uses cf_ruleset_apply_profile() which handles get-or-create + replace-all.
# =====================================
cf_update_rules () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local PROFILE_NAME=$3
    local OBJECT="${DOMAIN_NAME}/${ZONE_ID}"

    _running2 "Updating rules on $OBJECT via Rulesets API"

    local PROFILE_FILE="$PROFILE_DIR/$PROFILE_NAME.json"
    if [[ ! -f $PROFILE_FILE ]]; then
        _error "Profile file not found: $PROFILE_FILE"
        return 1
    fi

    if ! jq empty "$PROFILE_FILE" 2>/dev/null; then
        _error "Invalid JSON in $PROFILE_FILE"
        return 1
    fi

    local RULES_JSON
    RULES_JSON=$(_cf_ruleset_read_profile_rules "$PROFILE_FILE")
    if [[ -z "$RULES_JSON" || "$RULES_JSON" == "null" ]]; then
        _error "Failed to read rules from profile $PROFILE_NAME"
        return 1
    fi

    if cf_ruleset_apply_profile "$ZONE_ID" "$RULES_JSON"; then
        _success "Updated rules on $OBJECT"
        return 0
    else
        _error "Failed to update rules on $OBJECT"
        return 1
    fi
}

# =====================================
# -- cf_update_rules_profile $ZONE_ID $RULES_FILE
# -- Update rules from a JSON file using the Rulesets API.
# -- Deprecated: use cf_update_rules() or cf_create_rules_profile() instead.
# =====================================
function cf_update_rules_profile () {
    _warning "cf_update_rules_profile is deprecated. Use cf_update_rules() instead."
    local ZONE_ID=$1
    local RULES_FILE=$2

    if [[ ! -f "$RULES_FILE" ]]; then
        _error "Rules file not found: $RULES_FILE"
        return 1
    fi

    local RULES_JSON
    RULES_JSON=$(_cf_ruleset_read_profile_rules "$RULES_FILE")
    if [[ -z "$RULES_JSON" || "$RULES_JSON" == "null" ]]; then
        _error "Failed to read rules from $RULES_FILE"
        return 1
    fi

    cf_ruleset_apply_profile "$ZONE_ID" "$RULES_JSON"
}

# =============================================================================
# -- Upgrade Default Rules (Rulesets API)
# =============================================================================

# =====================================
# -- cf_upgrade_rules_default $DOMAIN_NAME $ZONE_ID $PROFILE_NAME
# -- Compare existing rule versions against the profile and upgrade if needed.
# -- Parses rule prefix format R#V### from existing rule descriptions.
# -- Uses replace-all (PUT) when any rule version differs.
# =====================================
function cf_upgrade_rules_default () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local PROFILE_NAME=$3
    local OBJECT="${DOMAIN_NAME}/${ZONE_ID}"
    local PROFILE_FILE="$PROFILE_DIR/$PROFILE_NAME.json"

    _running2 "Upgrading rules on $OBJECT"

    # -- Validate profile
    [[ ! -d $PROFILE_DIR ]] && _error "$PROFILE_DIR doesn't exist, failing" && exit 1
    [[ ! -f $PROFILE_FILE ]] && _error "Profile file not found: $PROFILE_FILE" && return 1

    # -- Get existing entry point
    if ! cf_ruleset_get_entrypoint "$ZONE_ID"; then
        _warning "No existing ruleset found for $OBJECT — creating new one from profile"
        local RULES_JSON
        RULES_JSON=$(_cf_ruleset_read_profile_rules "$PROFILE_FILE")
        cf_ruleset_apply_profile "$ZONE_ID" "$RULES_JSON"
        return $?
    fi

    # -- Parse existing rule versions from descriptions (R#V### format)
    local NEEDS_UPGRADE=false
    local EXISTING_DESCRIPTIONS
    EXISTING_DESCRIPTIONS=$(echo "$RULESET_API_OUTPUT" | jq -r '.result.rules[].description // empty')

    while IFS= read -r desc; do
        [[ -z "$desc" ]] && continue

        local RULE_PREFIX
        RULE_PREFIX=$(echo "$desc" | cut -d' ' -f1)

        # Parse format: R#V### (e.g., R1V205)
        if [[ "$RULE_PREFIX" =~ ^R([0-9]+)V([0-9]{3})$ ]]; then
            local RULE_NUMBER="${BASH_REMATCH[1]}"
            local RULE_VERSION="${BASH_REMATCH[2]}"

            # Get the profile version for this rule number
            local PROFILE_VERSION
            PROFILE_VERSION=$(jq -r --arg NUM "$RULE_NUMBER" '.rules[] | select(.rule_number == $NUM) | .rule_version' "$PROFILE_FILE")

            if [[ -n "$PROFILE_VERSION" && "$RULE_VERSION" != "$PROFILE_VERSION" ]]; then
                _warning "Rule R${RULE_NUMBER}: version $RULE_VERSION → $PROFILE_VERSION (upgrade needed)"
                NEEDS_UPGRADE=true
            fi
        else
            _debug "Skipping non-standard description format: '$desc'"
        fi
    done <<< "$EXISTING_DESCRIPTIONS"

    # -- No upgrade needed
    if [[ "$NEEDS_UPGRADE" == "false" ]]; then
        _success "All rules are up to date on $OBJECT"
        return 0
    fi

    # -- Upgrade: replace all rules from profile
    _running2 "Upgrading rules on $OBJECT..."
    local RULES_JSON
    RULES_JSON=$(_cf_ruleset_read_profile_rules "$PROFILE_FILE")
    if [[ -z "$RULES_JSON" || "$RULES_JSON" == "null" ]]; then
        _error "Failed to read rules from profile $PROFILE_NAME"
        return 1
    fi

    if cf_ruleset_apply_profile "$ZONE_ID" "$RULES_JSON"; then
        _success "Upgraded rules on $OBJECT"
        return 0
    else
        _error "Failed to upgrade rules on $OBJECT"
        return 1
    fi
}

# =============================================================================
# -- Single Rule Update (Rulesets API)
# =============================================================================

# =====================================
# -- cf_update_rule_profile $ZONE_ID $RULE_ID $RULE_NUMBER $PROFILE_NAME
# -- Update a single rule by applying the profile's rule data via PATCH.
# -- Requires the ruleset_id from the entry point.
# =====================================
function cf_update_rule_profile () {
    local ZONE_ID=$1
    local RULE_ID=$2
    local RULE_NUMBER=$3
    local PROFILE_NAME=$4

    _running2 "Updating rule $RULE_ID (R${RULE_NUMBER}) on zone $ZONE_ID via PATCH"

    local PROFILE_FILE="$PROFILE_DIR/$PROFILE_NAME.json"
    [[ ! -f $PROFILE_FILE ]] && _error "Profile file not found: $PROFILE_FILE" && return 1

    # -- Read specific rule from profile by rule_number
    local RULE_JSON
    RULE_JSON=$(jq -c --arg NUM "$RULE_NUMBER" '.rules[] | select(.rule_number == $NUM)' "$PROFILE_FILE")
    if [[ -z "$RULE_JSON" || "$RULE_JSON" == "null" ]]; then
        _error "Rule $RULE_NUMBER not found in profile $PROFILE_NAME"
        return 1
    fi

    # -- Get the entry point ruleset ID
    if ! cf_ruleset_get_entrypoint "$ZONE_ID"; then
        _error "No entry point ruleset found for zone $ZONE_ID"
        return 1
    fi
    local RULESET_ID
    RULESET_ID=$(echo "$RULESET_API_OUTPUT" | jq -r '.result.id')

    # -- Update the single rule via PATCH
    cf_ruleset_update_rule "$ZONE_ID" "$RULESET_ID" "$RULE_ID" "$RULE_JSON"
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
# -- Print rules from profile (supports v2 and v3 schemas)
# =====================================
function cf_print_profile () {
    PROFILE_NAME=$1
    PROFILE_FILE="$PROFILE_DIR/$PROFILE_NAME.json"
    if [[ ! -f $PROFILE_FILE ]]; then
        _error "Profile file not found: $PROFILE_FILE"
        return 1
    fi
    
    # Schema detection
    local SCHEMA_VERSION
    SCHEMA_VERSION=$(jq -r '.version // 2' "$PROFILE_FILE")
    local PHASE
    PHASE=$(jq -r '.phase // "http_request_firewall_custom (legacy)"' "$PROFILE_FILE")
    
    # Get rule count
    local RULE_COUNT
	RULE_COUNT=$(jq '.rules | length' "$PROFILE_FILE")
    
    echo ""
    echo -e "${CBLUEBG} Profile: $PROFILE_NAME ${NC}"
    echo -e "  ${CGRAY}Schema:${NC}     v$SCHEMA_VERSION"
    echo -e "  ${CGRAY}Phase:${NC}      $PHASE"
    echo -e "  ${CGRAY}Rules:${NC}      $RULE_COUNT"
    echo ""
    
    # Loop through each rule
    for ((i=0; i<RULE_COUNT; i++)); do
        # Extract common rule details
        local DESCRIPTION ACTION EXPRESSION ENABLED
		DESCRIPTION=$(jq -r ".rules[$i].description" "$PROFILE_FILE")
		ACTION=$(jq -r ".rules[$i].action" "$PROFILE_FILE")
        ENABLED=$(jq -r ".rules[$i].enabled // true" "$PROFILE_FILE")
		EXPRESSION=$(jq -r ".rules[$i].expression" "$PROFILE_FILE" | sed 's/\\"/"/g')
        
        # Build status line
        local STATUS_LINE=""
        STATUS_LINE="${CYELLOW}Rule $((i+1)): ${DESCRIPTION}${NC}"
        STATUS_LINE+=" (${CGREEN}Action: ${ACTION}${NC}"
        
        # Priority only for v2
        if [[ "$SCHEMA_VERSION" -lt 3 ]]; then
            local PRIORITY
            PRIORITY=$(jq -r ".rules[$i].priority // \"\"" "$PROFILE_FILE")
            if [[ -n "$PRIORITY" ]]; then
                STATUS_LINE+=", ${CGRAY}Priority: ${PRIORITY}${NC}"
            fi
        fi
        
        # Enabled status
        if [[ "$ENABLED" == "true" ]]; then
            STATUS_LINE+=", ${CGREEN}Enabled${NC}"
        else
            STATUS_LINE+=", ${CRED}Disabled${NC}"
        fi
        STATUS_LINE+=")"
        
        echo -e "$STATUS_LINE"
        
        # Logging (v3)
        if [[ "$SCHEMA_VERSION" -ge 3 ]]; then
            local LOGGING_ENABLED
            LOGGING_ENABLED=$(jq -r ".rules[$i].logging.enabled // true" "$PROFILE_FILE")
            if [[ "$LOGGING_ENABLED" == "false" ]]; then
                echo -e "  ${CDARKGRAY}Logging: Disabled${NC}"
            fi
        fi
        
        # Action parameters (v3)
        if [[ "$SCHEMA_VERSION" -ge 3 ]]; then
            local HAS_AP
            HAS_AP=$(jq '.rules[$i].action_parameters // {} | length' "$PROFILE_FILE")
            if [[ "$HAS_AP" -gt 0 ]]; then
                echo -e "  ${CDARKGRAY}Action Parameters:${NC}"
                jq -r ".rules[$i].action_parameters" "$PROFILE_FILE" | while IFS= read -r line; do
                    echo -e "    ${CDARKGRAY}$line${NC}"
                done
            fi
        fi
        
        # Expression
        echo -e "${CGREEN}Expression:${NC}"
        echo "$EXPRESSION" | while IFS= read -r line; do
            echo "  $line"
        done
        
        echo -e "${CCYAN}$(printf '=%.0s' {1..80})${NC}"
    done
}

# =====================================
# -- cf_validate_profile $PROFILE_NAME
# -- Validate a JSON profile file for syntax and structure errors
# =====================================
cf_validate_profile() {
    local PROFILE_NAME=$1
    local PROFILE_FILE="$PROFILE_DIR/$PROFILE_NAME.json"
    local total_errors=0
    
    if [[ -z "$PROFILE_NAME" ]]; then
        _error "No profile name provided"
        return 1
    fi
    
    _running2 "Validating profile: $PROFILE_NAME"
    
    # Check if file exists
    if [[ ! -f "$PROFILE_FILE" ]]; then
        _error "Profile file not found: $PROFILE_FILE"
        return 1
    fi
    
    # Step 1: JSON syntax validation
    _debug "Checking JSON syntax..."
    if ! jq empty "$PROFILE_FILE" 2>/dev/null; then
        _error "Invalid JSON syntax in $PROFILE_FILE"
        return 1
    fi
    _success "JSON syntax is valid"
    
    # Step 2: Structure validation
    _debug "Checking JSON structure..."
    
    # Check required top-level fields
    local required_fields=("name" "description" "rules")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$PROFILE_FILE" >/dev/null 2>&1; then
            _error "Missing required field: '$field'"
            ((total_errors++))
        fi
    done
    
    # Check if rules is an array
    if ! jq -e '.rules | type == "array"' "$PROFILE_FILE" >/dev/null 2>&1; then
        _error "'rules' must be an array"
        ((total_errors++))
    fi
    
    # Step 3: Detect schema version
    local SCHEMA_VERSION
    SCHEMA_VERSION=$(jq -r '.version // 2' "$PROFILE_FILE")
    
    if [[ "$SCHEMA_VERSION" -ge 3 ]]; then
        _running2 "Detected v3 schema (version=$SCHEMA_VERSION)"
    else
        _warning "Profile uses v$SCHEMA_VERSION schema. Consider upgrading to v3 for full Rulesets API support."
    fi
    
    # Step 4: Rules validation
    local rule_count
    rule_count=$(jq '.rules | length' "$PROFILE_FILE" 2>/dev/null || echo "0")
    _debug "Validating $rule_count rules..."
    
    # Common rule fields (both v2 and v3)
    local common_fields=("rule_number" "rule_version" "description" "expression" "action")
    
    for ((i=0; i<rule_count; i++)); do
        local rule_num=$((i+1))
        _debug "Checking rule $rule_num..."
        
        # Check common required rule fields
        for field in "${common_fields[@]}"; do
            if ! jq -e ".rules[$i].$field" "$PROFILE_FILE" >/dev/null 2>&1; then
                _error "Rule $rule_num: Missing required field '$field'"
                ((total_errors++))
            fi
        done
        
        # v2-specific checks
        if [[ "$SCHEMA_VERSION" -lt 3 ]]; then
            # v2 requires priority
            if ! jq -e ".rules[$i].priority" "$PROFILE_FILE" >/dev/null 2>&1; then
                _error "Rule $rule_num: Missing required v2 field 'priority'"
                ((total_errors++))
            fi
            
            # Validate v2 priority is a number
            local priority
            priority=$(jq -r ".rules[$i].priority" "$PROFILE_FILE" 2>/dev/null)
            if [[ -n "$priority" && "$priority" != "null" ]]; then
                if ! [[ "$priority" =~ ^[0-9]+$ ]]; then
                    _error "Rule $rule_num: Priority must be a number, got '$priority'"
                    ((total_errors++))
                fi
            fi
        fi
        
        # v3-specific checks
        if [[ "$SCHEMA_VERSION" -ge 3 ]]; then
            # v3 does not use priority
            if jq -e ".rules[$i].priority" "$PROFILE_FILE" >/dev/null 2>&1; then
                local v3_priority
                v3_priority=$(jq -r ".rules[$i].priority" "$PROFILE_FILE")
                if [[ -n "$v3_priority" && "$v3_priority" != "null" ]]; then
                    _warning "Rule $rule_num: v3 schema does not use 'priority' field (order is array position)"
                fi
            fi
            
            # Validate enabled is boolean if present
            if jq -e ".rules[$i].enabled" "$PROFILE_FILE" >/dev/null 2>&1; then
                local enabled_type
                enabled_type=$(jq -r ".rules[$i].enabled | type" "$PROFILE_FILE")
                if [[ "$enabled_type" != "boolean" ]]; then
                    _error "Rule $rule_num: 'enabled' must be a boolean, got $enabled_type"
                    ((total_errors++))
                fi
            fi
            
            # Validate logging.enabled is boolean if present
            if jq -e ".rules[$i].logging.enabled" "$PROFILE_FILE" >/dev/null 2>&1; then
                local logging_type
                logging_type=$(jq -r ".rules[$i].logging.enabled | type" "$PROFILE_FILE")
                if [[ "$logging_type" != "boolean" ]]; then
                    _error "Rule $rule_num: 'logging.enabled' must be a boolean, got $logging_type"
                    ((total_errors++))
                fi
            fi
        fi
        
        # Validate action values (combined list for both schemas)
        local action
        action=$(jq -r ".rules[$i].action" "$PROFILE_FILE" 2>/dev/null)
        if [[ -n "$action" && "$action" != "null" ]]; then
            # v2 and v3 share common actions; v3 adds 'skip' and 'execute'
            case "$action" in
                "allow"|"block"|"challenge"|"js_challenge"|"managed_challenge"|"log"|"bypass"|"skip"|"execute")
                    # Valid actions
                    ;;
                *)
                    _error "Rule $rule_num: Invalid action '$action'"
                    _error "Valid actions: allow, block, challenge, js_challenge, managed_challenge, log, bypass (v2), skip, execute (v3)"
                    ((total_errors++))
                    ;;
            esac
        fi
        
        # Validate expression syntax (basic parentheses check)
        local expression
        expression=$(jq -r ".rules[$i].expression" "$PROFILE_FILE" 2>/dev/null)
        if [[ -n "$expression" && "$expression" != "null" ]]; then
            if ! _validate_expression_syntax "$expression" "$rule_num"; then
                ((total_errors++))
            fi
        fi
    done
    
    # Summary
    if [ $total_errors -eq 0 ]; then
        _success "✓ Profile validation passed: $PROFILE_NAME"
        
        # Show profile summary
        local name description
        name=$(jq -r '.name' "$PROFILE_FILE")
        description=$(jq -r '.description' "$PROFILE_FILE")
        
        echo ""
        echo "Profile Summary:"
        echo "  Name: $name"
        echo "  Description: $description"  
        echo "  Rules: $rule_count"
        
        return 0
    else
        _error "✗ Profile validation failed with $total_errors errors: $PROFILE_NAME"
        return 1
    fi
}

# =====================================
# -- _validate_expression_syntax $expression $rule_num
# -- Basic expression syntax validation (helper function)
# =====================================
_validate_expression_syntax() {
    local expression="$1"
    local rule_num="$2"
    local paren_count=0
    local i=0
    
    # Check for balanced parentheses
    while [ $i -lt ${#expression} ]; do
        char="${expression:$i:1}"
        case "$char" in
            "(")
                ((paren_count++))
                ;;
            ")")
                ((paren_count--))
                if [ $paren_count -lt 0 ]; then
                    _error "Rule $rule_num: Unmatched closing parenthesis at position $i"
                    return 1
                fi
                ;;
        esac
        ((i++))
    done
    
    if [ $paren_count -ne 0 ]; then
        _error "Rule $rule_num: Unbalanced parentheses: $paren_count unmatched opening parentheses"
        return 1
    fi
    
    # Check for empty expression
    if [[ -z "${expression// /}" ]]; then
        _error "Rule $rule_num: Empty expression"
        return 1
    fi
    
    return 0
}