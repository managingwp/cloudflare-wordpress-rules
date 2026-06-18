#!/usr/bin/env bash
# =================================================================================================
# cf-inc-rulesets.sh v1.0.0
# Rulesets API functions for Cloudflare WordPress Rules
# 
# This file implements the Cloudflare Rulesets API for managing WAF custom rules.
# API Reference: https://developers.cloudflare.com/api/resources/rulesets/
#
# Deprecation Notice:
# The Firewall Rules API and Filters API were deprecated on 2025-06-15.
# All operations should use the Rulesets API going forward.
#
# Phase entry point for custom rules:
#   GET  /client/v4/zones/{zone_id}/rulesets/phases/http_request_firewall_custom/entrypoint
#   POST /client/v4/zones/{zone_id}/rulesets
#   PUT  /client/v4/zones/{zone_id}/rulesets/{ruleset_id}
#   POST /client/v4/zones/{zone_id}/rulesets/{ruleset_id}/rules
#   PATCH /client/v4/zones/{zone_id}/rulesets/{ruleset_id}/rules/{rule_id}
#   DELETE /client/v4/zones/{zone_id}/rulesets/{ruleset_id}/rules/{rule_id}
# =================================================================================================

# =====================================
# -- Variables
# =====================================
RULESETS_LIB_VERSION="1.0.0"
declare -a cf_ruleset_functions

# =============================================================================
# -- Function Index
# =============================================================================

# Each function should be registered in cf_ruleset_functions with a description.
# Use the format:
#   cf_ruleset_functions["function_name"]="Brief description"

# Naming convention:
#   cf_ruleset_<verb>_<noun>()  — Public functions
#   _cf_ruleset_<verb>_<noun>() — Internal/helper functions

# =====================================
# -- _list_ruleset_functions
# -- List all ruleset functions
# =====================================
cf_ruleset_functions["_list_ruleset_functions"]="List all ruleset functions"
function _list_ruleset_functions () {
    _running "Listing all ruleset functions with descriptions"
    # Print header
    printf "%-50s | %-50s | %s\n" "Function" "Description" "Count"
    printf "%s-+-%s-+-%s\n" "$(printf '%0.s-' {1..50})" "$(printf '%0.s-' {1..50})" "$(printf '%0.s-' {1..10})"
    
    # Loop through array, printing key and value
    for FUNC_NAME in "${!cf_ruleset_functions[@]}"; do
        # -- Count how many times the function is used in the script
        FUNC_COUNT=$(grep -c "$FUNC_NAME" "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/inc/*.sh 2>/dev/null || echo "0")
        DESCRIPTION="${cf_ruleset_functions[$FUNC_NAME]}"
        printf "%-50s | %-50s | %s\n" "$FUNC_NAME" "$DESCRIPTION" "$FUNC_COUNT"
    done
}

# =====================================
# -- cf_ruleset_api_version
# -- Print the ruleset library version
# =====================================
cf_ruleset_functions["cf_ruleset_api_version"]="Print ruleset library version"
function cf_ruleset_api_version () {
    echo "cf-inc-rulesets.sh version $RULESETS_LIB_VERSION"
}

# =====================================
# -- cf_ruleset_phase_name
# -- Print the WAF custom rules phase name
# =====================================
cf_ruleset_functions["cf_ruleset_phase_name"]="Print the WAF custom rules phase name"
function cf_ruleset_phase_name () {
    echo "http_request_firewall_custom"
}

# =============================================================================
# -- Internal Helpers
# =============================================================================

# =====================================
# -- _cf_ruleset_api $REQUEST $API_PATH [$EXTRA...]
# -- Internal curl wrapper for Rulesets API operations.
# -- Unlike cf_api(), this does NOT exit on non-200 responses,
# -- making it safe for handling 404 (entry point not found).
# --
# -- Sets global: RULESET_API_OUTPUT, RULESET_CURL_EXIT_CODE
# -- Returns: 0 always (check RULESET_CURL_EXIT_CODE for HTTP status)
# =====================================
cf_ruleset_functions["_cf_ruleset_api"]="Internal curl wrapper for Rulesets API"
function _cf_ruleset_api () {
    local REQUEST=$1
    local API_PATH=$2
    shift 2
    local EXTRA=("$@")
    
    local CURL_HEADERS=()
    if [[ -n $API_ACCOUNT && -n $API_APIKEY ]]; then
        CURL_HEADERS=("-H" "X-Auth-Key: ${API_APIKEY}" -H "X-Auth-Email: ${API_ACCOUNT}")
        _debug "Using API_KEY auth for Rulesets API"
    elif [[ -n $API_TOKEN ]]; then
        CURL_HEADERS=("-H" "Authorization: Bearer ${API_TOKEN}")
        _debug "Using API_TOKEN auth for Rulesets API"
    else
        _error "No API Token or API Key found for Rulesets API"
        RULESET_CURL_EXIT_CODE=0
        RULESET_API_OUTPUT='{"success":false,"errors":[{"code":0,"message":"No authentication configured"}]}'
        return 1
    fi
    
    local CURL_OUTPUT
    CURL_OUTPUT=$(mktemp)
    
    RULESET_CURL_EXIT_CODE=$(curl -s --output "$CURL_OUTPUT" -w "%{http_code}" \
        --request "$REQUEST" \
        --url "${API_URL}${API_PATH}" \
        "${CURL_HEADERS[@]}" \
        "${EXTRA[@]}")
    RULESET_API_OUTPUT=$(<"$CURL_OUTPUT")
    rm "$CURL_OUTPUT"
    
    _debug "Rulesets API: $REQUEST $API_PATH → $RULESET_CURL_EXIT_CODE"
    _debug_json "$RULESET_API_OUTPUT"
    
    return 0
}

# =============================================================================
# -- Entry Point Management
# =============================================================================

# =====================================
# -- cf_ruleset_get_entrypoint $ZONE_ID
# -- Get the http_request_firewall_custom phase entry point ruleset.
# -- Returns: Full API response JSON via RULESET_API_OUTPUT (and stdout)
# -- Exit code: 0 if exists, 1 if not yet created (404), 2 on error
# =====================================
cf_ruleset_functions["cf_ruleset_get_entrypoint"]="Get phase entry point ruleset"
function cf_ruleset_get_entrypoint () {
    local ZONE_ID=$1
    local PHASE
    PHASE=$(cf_ruleset_phase_name)
    
    _debug "function:${FUNCNAME[0]} - Getting entry point ruleset for phase $PHASE on zone $ZONE_ID"
    
    _cf_ruleset_api GET "/client/v4/zones/${ZONE_ID}/rulesets/phases/${PHASE}/entrypoint"
    
    if [[ $RULESET_CURL_EXIT_CODE == "200" ]]; then
        _debug "Entry point ruleset found for zone $ZONE_ID"
        echo "$RULESET_API_OUTPUT"
        return 0
    elif [[ $RULESET_CURL_EXIT_CODE == "404" ]]; then
        _debug "Entry point ruleset not yet created for zone $ZONE_ID"
        return 1
    else
        _error "Error getting entry point ruleset (HTTP $RULESET_CURL_EXIT_CODE)"
        parse_cf_error "$RULESET_API_OUTPUT"
        return 2
    fi
}

# =====================================
# -- cf_ruleset_create_entrypoint $ZONE_ID $RULES_JSON [$NAME]
# -- Create the phase entry point ruleset with initial rules.
# -- If no name is provided, defaults to "Cloudflare WordPress Rules".
# -- Returns: new ruleset ID via stdout
# =====================================
cf_ruleset_functions["cf_ruleset_create_entrypoint"]="Create phase entry point ruleset"
function cf_ruleset_create_entrypoint () {
    local ZONE_ID=$1
    local RULES_JSON=$2
    local NAME=${3:-"Cloudflare WordPress Rules"}
    local PHASE
    PHASE=$(cf_ruleset_phase_name)
    
    _debug "function:${FUNCNAME[0]} - Creating entry point ruleset '$NAME' for phase $PHASE on zone $ZONE_ID"
    
    # Build the POST body
    local POST_DATA
    POST_DATA=$(jq -n \
        --arg name "$NAME" \
        --arg kind "zone" \
        --arg phase "$PHASE" \
        --argjson rules "$RULES_JSON" \
        '{
            name: $name,
            kind: $kind,
            phase: $phase,
            rules: $rules
        }')
    
    _cf_ruleset_api POST "/client/v4/zones/${ZONE_ID}/rulesets" \
        -H "Content-Type: application/json" \
        -d "$POST_DATA"
    
    if [[ $RULESET_CURL_EXIT_CODE == "200" ]]; then
        local NEW_ID
        NEW_ID=$(echo "$RULESET_API_OUTPUT" | jq -r '.result.id')
        _success "Created entry point ruleset: $NEW_ID"
        echo "$NEW_ID"
        return 0
    else
        _error "Failed to create entry point ruleset (HTTP $RULESET_CURL_EXIT_CODE)"
        parse_cf_error "$RULESET_API_OUTPUT"
        return 1
    fi
}

# =====================================
# -- cf_ruleset_replace_all_rules $ZONE_ID $RULESET_ID $RULES_JSON
# -- Replace all rules in a ruleset (bulk PUT operation).
# -- CAUTION: This replaces ALL existing rules. Include existing rule IDs
# -- in the rules array if you want to preserve them.
# -- Returns: updated ruleset JSON via stdout
# =====================================
cf_ruleset_functions["cf_ruleset_replace_all_rules"]="Replace all rules in a ruleset"
function cf_ruleset_replace_all_rules () {
    local ZONE_ID=$1
    local RULESET_ID=$2
    local RULES_JSON=$3
    
    _debug "function:${FUNCNAME[0]} - Replacing all rules in ruleset $RULESET_ID on zone $ZONE_ID"
    
    local PUT_DATA
    PUT_DATA=$(jq -n \
        --argjson rules "$RULES_JSON" \
        '{rules: $rules}')
    
    _cf_ruleset_api PUT "/client/v4/zones/${ZONE_ID}/rulesets/${RULESET_ID}" \
        -H "Content-Type: application/json" \
        -d "$PUT_DATA"
    
    if [[ $RULESET_CURL_EXIT_CODE == "200" ]]; then
        _success "Replaced all rules in ruleset $RULESET_ID"
        echo "$RULESET_API_OUTPUT"
        return 0
    else
        _error "Failed to replace rules in ruleset $RULESET_ID (HTTP $RULESET_CURL_EXIT_CODE)"
        parse_cf_error "$RULESET_API_OUTPUT"
        return 1
    fi
}

# =============================================================================
# -- Single Rule Operations
# =============================================================================

# =====================================
# -- cf_ruleset_add_rule $ZONE_ID $RULESET_ID $RULE_JSON [$POSITION_JSON]
# -- Add a single rule to an existing ruleset.
# -- Optional: pass a position JSON object to control rule ordering, e.g.:
# --   '{"index": 0}' or '{"after": "<RULE_ID>"}' or '{"before": "<RULE_ID>"}'
# -- Returns: new rule ID via stdout
# =====================================
cf_ruleset_functions["cf_ruleset_add_rule"]="Add a single rule to a ruleset"
function cf_ruleset_add_rule () {
    local ZONE_ID=$1
    local RULESET_ID=$2
    local RULE_JSON=$3
    local POSITION_JSON=${4:-}
    
    _debug "function:${FUNCNAME[0]} - Adding rule to ruleset $RULESET_ID on zone $ZONE_ID"
    
    # Build POST data: rule JSON with optional position
    local POST_DATA
    if [[ -n "$POSITION_JSON" ]]; then
        POST_DATA=$(echo "$RULE_JSON" | jq --argjson position "$POSITION_JSON" '. + {position: $position}')
    else
        POST_DATA="$RULE_JSON"
    fi
    
    _cf_ruleset_api POST "/client/v4/zones/${ZONE_ID}/rulesets/${RULESET_ID}/rules" \
        -H "Content-Type: application/json" \
        -d "$POST_DATA"
    
    if [[ $RULESET_CURL_EXIT_CODE == "200" ]]; then
        local NEW_RULE_ID
        NEW_RULE_ID=$(echo "$RULESET_API_OUTPUT" | jq -r '.result.id')
        _success "Added rule: $NEW_RULE_ID"
        echo "$NEW_RULE_ID"
        return 0
    else
        _error "Failed to add rule to ruleset $RULESET_ID (HTTP $RULESET_CURL_EXIT_CODE)"
        parse_cf_error "$RULESET_API_OUTPUT"
        return 1
    fi
}

# =====================================
# -- cf_ruleset_update_rule $ZONE_ID $RULESET_ID $RULE_ID $RULE_JSON
# -- Update a single rule in a ruleset (PATCH).
# -- Only the fields provided in $RULE_JSON will be updated.
# -- Returns: updated rule JSON via stdout
# =====================================
cf_ruleset_functions["cf_ruleset_update_rule"]="Update a single rule in a ruleset"
function cf_ruleset_update_rule () {
    local ZONE_ID=$1
    local RULESET_ID=$2
    local RULE_ID=$3
    local RULE_JSON=$4
    
    _debug "function:${FUNCNAME[0]} - Updating rule $RULE_ID in ruleset $RULESET_ID on zone $ZONE_ID"
    
    _cf_ruleset_api PATCH "/client/v4/zones/${ZONE_ID}/rulesets/${RULESET_ID}/rules/${RULE_ID}" \
        -H "Content-Type: application/json" \
        -d "$RULE_JSON"
    
    if [[ $RULESET_CURL_EXIT_CODE == "200" ]]; then
        _success "Updated rule: $RULE_ID"
        echo "$RULESET_API_OUTPUT"
        return 0
    else
        _error "Failed to update rule $RULE_ID (HTTP $RULESET_CURL_EXIT_CODE)"
        parse_cf_error "$RULESET_API_OUTPUT"
        return 1
    fi
}

# =====================================
# -- cf_ruleset_delete_rule $ZONE_ID $RULESET_ID $RULE_ID
# -- Delete a single rule from a ruleset.
# =====================================
cf_ruleset_functions["cf_ruleset_delete_rule"]="Delete a single rule from a ruleset"
function cf_ruleset_delete_rule () {
    local ZONE_ID=$1
    local RULESET_ID=$2
    local RULE_ID=$3
    
    _debug "function:${FUNCNAME[0]} - Deleting rule $RULE_ID from ruleset $RULESET_ID on zone $ZONE_ID"
    
    _cf_ruleset_api DELETE "/client/v4/zones/${ZONE_ID}/rulesets/${RULESET_ID}/rules/${RULE_ID}"
    
    if [[ $RULESET_CURL_EXIT_CODE == "200" ]]; then
        _success "Deleted rule: $RULE_ID"
        return 0
    else
        _error "Failed to delete rule $RULE_ID (HTTP $RULESET_CURL_EXIT_CODE)"
        parse_cf_error "$RULESET_API_OUTPUT"
        return 1
    fi
}

# =============================================================================
# -- Listing & Query
# =============================================================================

# =====================================
# -- cf_ruleset_list_rules $ZONE_ID [$TABLE_ONLY]
# -- List all rules from the http_request_firewall_custom entry point.
# -- If TABLE_ONLY=1, prints a compact table with numbered entries.
# -- Returns: raw ruleset JSON via RULESET_API_OUTPUT
# =====================================
cf_ruleset_functions["cf_ruleset_list_rules"]="List rules from entry point ruleset"
function cf_ruleset_list_rules () {
    local ZONE_ID=$1
    local TABLE_ONLY=${2:-0}
    
    _debug "function:${FUNCNAME[0]} - Listing rules from entry point on zone $ZONE_ID"
    
    cf_ruleset_get_entrypoint "$ZONE_ID"
    local GET_EXIT=$?
    if [[ $GET_EXIT -ne 0 ]]; then
        if [[ $GET_EXIT -eq 1 ]]; then
            _warning "No WAF custom rules found for zone $ZONE_ID (entry point not created yet)"
        else
            _error "Failed to retrieve rules for zone $ZONE_ID"
        fi
        return 1
    fi
    
    # Extract the rules array from the entry point response
    local RULES
    RULES=$(echo "$RULESET_API_OUTPUT" | jq -r '.result.rules // []')
    local RULE_COUNT
    RULE_COUNT=$(echo "$RULES" | jq 'length')
    
    if [[ "$RULE_COUNT" -eq 0 ]]; then
        _warning "No rules in the entry point ruleset for zone $ZONE_ID"
        echo "$RULESET_API_OUTPUT"
        return 0
    fi
    
    if [[ $TABLE_ONLY -eq 1 ]]; then
        # Compact numbered list
        echo "$RULESET_API_OUTPUT" | jq -r '.result.rules[] | "\(.id) \(.description // "(no description)")"' | \
            awk '{print "#" NR, $0}'
    else
        _success "Found $RULE_COUNT rule(s) in entry point ruleset"
        echo ""
        echo "$RULESET_API_OUTPUT" | jq -r '.result.rules[] | "\(.id) [\(.action)] \(.description // "(no description)")"'
        echo ""
        echo "$RULESET_API_OUTPUT"
    fi
    
    return 0
}

# =====================================
# -- cf_ruleset_get_rule $ZONE_ID $RULESET_ID $RULE_ID
# -- Get a single rule by ID from a specific ruleset.
# -- Returns: rule JSON via stdout
# =====================================
cf_ruleset_functions["cf_ruleset_get_rule"]="Get a single rule from a ruleset"
function cf_ruleset_get_rule () {
    local ZONE_ID=$1
    local RULESET_ID=$2
    local RULE_ID=$3
    
    _debug "function:${FUNCNAME[0]} - Getting rule $RULE_ID from ruleset $RULESET_ID on zone $ZONE_ID"
    
    _cf_ruleset_api GET "/client/v4/zones/${ZONE_ID}/rulesets/${RULESET_ID}/rules/${RULE_ID}"
    
    if [[ $RULESET_CURL_EXIT_CODE == "200" ]]; then
        echo "$RULESET_API_OUTPUT"
        return 0
    else
        _error "Failed to get rule $RULE_ID (HTTP $RULESET_CURL_EXIT_CODE)"
        parse_cf_error "$RULESET_API_OUTPUT"
        return 1
    fi
}

# =============================================================================
# -- Combined Helpers
# =============================================================================

# =====================================
# -- _cf_ruleset_get_or_create_entrypoint $ZONE_ID [$RULES_JSON]
# -- Get the existing entry point ruleset, or create a new one if none exists.
# -- If RULES_JSON is provided and a new ruleset is created, those rules
# -- will be included in the initial creation.
# -- Returns: ruleset ID (via stdout)
# -- Sets: GET_OR_CREATE_WAS_CREATED=1 if newly created
# =====================================
cf_ruleset_functions["_cf_ruleset_get_or_create_entrypoint"]="Get or create entry point ruleset"
function _cf_ruleset_get_or_create_entrypoint () {
    local ZONE_ID=$1
    local RULES_JSON=${2:-"[]"}
    
    _debug "function:${FUNCNAME[0]} - Getting or creating entry point on zone $ZONE_ID"
    
    # Try to get existing entry point.
    # Redirect stdout to /dev/null: cf_ruleset_get_entrypoint echoes the full
    # API response JSON, but we only need the exit code + RULESET_API_OUTPUT global.
    cf_ruleset_get_entrypoint "$ZONE_ID" > /dev/null
    local GET_EXIT=$?
    if [[ $GET_EXIT -eq 0 ]]; then
        # Entry point exists - extract ruleset ID from global variable
        local RULESET_ID
        RULESET_ID=$(echo "$RULESET_API_OUTPUT" | jq -r '.result.id')
        _debug "Existing entry point ruleset found: $RULESET_ID"
        # shellcheck disable=SC2034
        GET_OR_CREATE_WAS_CREATED=0
        echo "$RULESET_ID"
        return 0
    fi
    
    if [[ $GET_EXIT -eq 1 ]]; then
        # 404 - not found, create a new one
        _debug "Entry point not found, creating new one"
        local NEW_ID
        NEW_ID=$(cf_ruleset_create_entrypoint "$ZONE_ID" "$RULES_JSON")
        local CREATE_EXIT=$?
        
        if [[ $CREATE_EXIT -eq 0 ]]; then
            # shellcheck disable=SC2034
            GET_OR_CREATE_WAS_CREATED=1
            echo "$NEW_ID"
            return 0
        else
            _error "Failed to create entry point ruleset"
            return 1
        fi
    else
        # Other error
        _error "Failed to get entry point ruleset"
        return 1
    fi
}

# =====================================
# -- cf_ruleset_apply_profile $ZONE_ID $RULES_JSON
# -- Apply a set of rules to a zone via the entry point ruleset.
# -- This is the high-level function used by create-rules.
# -- Uses get-or-create and replace-all in one step.
# -- Returns: ruleset ID via stdout
# =====================================
cf_ruleset_functions["cf_ruleset_apply_profile"]="Apply rules to zone via entry point"
function cf_ruleset_apply_profile () {
    local ZONE_ID=$1
    local RULES_JSON=$2
    
    _debug "function:${FUNCNAME[0]} - Applying profile to zone $ZONE_ID"
    
    local RULESET_ID
    RULESET_ID=$(_cf_ruleset_get_or_create_entrypoint "$ZONE_ID" "$RULES_JSON")
    local EP_EXIT=$?
    
    if [[ $EP_EXIT -ne 0 ]]; then
        _error "Could not obtain entry point ruleset for zone $ZONE_ID"
        return 1
    fi
    
    # If it was newly created with rules already, we're done
    if [[ $GET_OR_CREATE_WAS_CREATED -eq 1 ]] && [[ "$RULES_JSON" != "[]" ]]; then
        _success "Entry point created with rules for zone $ZONE_ID"
        echo "$RULESET_ID"
        return 0
    fi
    
    # Existing ruleset found — confirm replacement unless SKIP_CONFIRM is set
    if [[ "${SKIP_CONFIRM:-0}" -ne 1 ]]; then
        local existing_count new_count
        existing_count=$(echo "$RULESET_API_OUTPUT" | jq '.result.rules | length // 0')
        new_count=$(echo "$RULES_JSON" | jq 'length')
        
        echo ""
        _warning "This zone already has ${existing_count} rule(s) in the entry point ruleset."
        _warning "The profile contains ${new_count} rule(s)."
        read -p "Replace all existing rules? [y/N]: " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            _warning "Operation cancelled by user"
            return 1
        fi
    fi
    
    # Replace all rules
    if ! cf_ruleset_replace_all_rules "$ZONE_ID" "$RULESET_ID" "$RULES_JSON"; then
        _error "Failed to apply rules to zone $ZONE_ID"
        return 1
    fi
    
    echo "$RULESET_ID"
    return 0
}

# =============================================================================
# -- Utility Functions
# =============================================================================

# =====================================
# -- cf_ruleset_build_rule_payload $EXPRESSION $ACTION [$DESCRIPTION] [$ENABLED]
# -- Build a JSON payload for a single rule
# -- Returns: JSON string via stdout
# =====================================
cf_ruleset_functions["cf_ruleset_build_rule_payload"]="Build a JSON payload for a single rule"
function cf_ruleset_build_rule_payload () {
    local EXPRESSION=$1
    local ACTION=$2
    local DESCRIPTION=${3:-""}
    local ENABLED=${4:-true}
    local LOGGING_ENABLED=${5:-true}
    local ACTION_PARAMETERS=${6:-"{}"}
    
    _debug "function:${FUNCNAME[0]} - Building rule payload: action=$ACTION"
    
    # Build logging object
    local LOGGING_JSON
    LOGGING_JSON=$(jq -n --argjson enabled "$LOGGING_ENABLED" '{enabled: $enabled}')
    
    # Build rule JSON with optional fields
    local RULE_JSON
    RULE_JSON=$(jq -n \
        --arg expression "$EXPRESSION" \
        --arg action "$ACTION" \
        --arg description "$DESCRIPTION" \
        --argjson enabled "$ENABLED" \
        --argjson logging "$LOGGING_JSON" \
        --argjson action_parameters "$ACTION_PARAMETERS" \
        '{
            expression: $expression,
            action: $action,
            description: $description,
            enabled: $enabled,
            logging: $logging,
            action_parameters: $action_parameters
        }')
    
    # Strip empty action_parameters to keep payload clean
    RULE_JSON=$(echo "$RULE_JSON" | jq 'if .action_parameters == {} then del(.action_parameters) else . end')
    
    echo "$RULE_JSON"
}

# =====================================
# -- cf_ruleset_build_rule_payload_skip $DESCRIPTION $EXPRESSION [$RULESET] [${PHASES[@]}]
# -- Build a JSON payload for a Skip action rule.
# -- Skip can be configured to skip all remaining custom rules, specific phases, or both.
# -- Examples:
# --   Skip all remaining custom rules:      cf_ruleset_build_rule_payload_skip "desc" "expr" "current"
# --   Skip specific security products:      cf_ruleset_build_rule_payload_skip "desc" "expr" "" "http_ratelimit"
# --   Skip all remaining rules + products:  cf_ruleset_build_rule_payload_skip "desc" "expr" "current" "http_ratelimit" "http_request_firewall_managed"
# =====================================
cf_ruleset_functions["cf_ruleset_build_rule_payload_skip"]="Build a JSON payload for a Skip action rule"
function cf_ruleset_build_rule_payload_skip () {
    local DESCRIPTION=$1
    local EXPRESSION=$2
    local RULESET=${3:-}           # "current" to skip remaining custom rules
    shift 3
    local PHASES=("$@")            # e.g. "http_ratelimit" "http_request_firewall_managed"
    
    _debug "function:${FUNCNAME[0]} - Building skip rule: ${DESCRIPTION}"
    
    # Build action_parameters
    local AP_JSON="{}"
    
    if [[ -n "$RULESET" ]]; then
        AP_JSON=$(echo "$AP_JSON" | jq --arg rs "$RULESET" '. + {ruleset: $rs}')
    fi
    
    if [[ ${#PHASES[@]} -gt 0 ]]; then
        local PHASES_JSON
        PHASES_JSON=$(printf '%s\n' "${PHASES[@]}" | jq -R . | jq -s .)
        AP_JSON=$(echo "$AP_JSON" | jq --argjson phases "$PHASES_JSON" '. + {phases: $phases}')
    fi
    
    # Skip rules typically disable logging to avoid noise on legitimate traffic
    cf_ruleset_build_rule_payload "$EXPRESSION" "skip" "$DESCRIPTION" "true" "false" "$AP_JSON"
}

# =====================================
# -- cf_ruleset_build_rule_payload_block $DESCRIPTION $EXPRESSION [$STATUS_CODE] [$CONTENT] [$CONTENT_TYPE]
# -- Build a JSON payload for a Block action with optional custom response.
# -- Default: 403, "Blocked by Cloudflare WordPress Rules", "text/plain"
# =====================================
cf_ruleset_functions["cf_ruleset_build_rule_payload_block"]="Build a JSON payload for a Block action with custom response"
function cf_ruleset_build_rule_payload_block () {
    local DESCRIPTION=$1
    local EXPRESSION=$2
    local STATUS_CODE=${3:-403}
    local CONTENT=${4:-"Blocked by Cloudflare WordPress Rules"}
    local CONTENT_TYPE=${5:-"text/plain"}
    
    _debug "function:${FUNCNAME[0]} - Building block rule with custom response: ${DESCRIPTION}"
    
    local AP_JSON
    AP_JSON=$(jq -n \
        --argjson status_code "$STATUS_CODE" \
        --arg content "$CONTENT" \
        --arg content_type "$CONTENT_TYPE" \
        '{
            response: {
                status_code: $status_code,
                content: $content,
                content_type: $content_type
            }
        }')
    
    cf_ruleset_build_rule_payload "$EXPRESSION" "block" "$DESCRIPTION" "true" "true" "$AP_JSON"
}

# =====================================
# -- cf_ruleset_build_rule_payload_ratelimit $DESCRIPTION $EXPRESSION $CHARACTERISTICS $PERIOD $REQUESTS_PER_PERIOD [$MITIGATION_TIMEOUT]
# -- Build a JSON payload for a rate limiting rule.
# =====================================
cf_ruleset_functions["cf_ruleset_build_rule_payload_ratelimit"]="Build a JSON payload for a rate limiting rule"
function cf_ruleset_build_rule_payload_ratelimit () {
    local DESCRIPTION=$1
    local EXPRESSION=$2
    local CHARACTERISTICS=$3       # JSON array, e.g. '["ip.src"]'
    local PERIOD=$4                # in seconds (e.g. 60)
    local REQUESTS_PER_PERIOD=$5   # threshold
    local MITIGATION_TIMEOUT=${6:-300}  # in seconds
    
    _debug "function:${FUNCNAME[0]} - Building rate limit rule: ${DESCRIPTION}"
    
    local AP_JSON
    AP_JSON=$(jq -n \
        --argjson characteristics "$CHARACTERISTICS" \
        --argjson period "$PERIOD" \
        --argjson requests_per_period "$REQUESTS_PER_PERIOD" \
        --argjson mitigation_timeout "$MITIGATION_TIMEOUT" \
        '{
            ratelimit: {
                characteristics: $characteristics,
                period: $period,
                requests_per_period: $requests_per_period,
                mitigation_timeout: $mitigation_timeout
            }
        }')
    
    cf_ruleset_build_rule_payload "$EXPRESSION" "block" "$DESCRIPTION" "true" "true" "$AP_JSON"
}

# =====================================
# -- cf_ruleset_validate_action $ACTION
# -- Validate that an action is supported by the Rulesets API
# -- Returns: 0 if valid, 1 if invalid
# =====================================
cf_ruleset_functions["cf_ruleset_validate_action"]="Validate a Rulesets API action"
function cf_ruleset_validate_action () {
    local ACTION=$1
    local VALID_ACTIONS=("block" "challenge" "js_challenge" "managed_challenge" "log" "skip" "execute")
    
    for valid in "${VALID_ACTIONS[@]}"; do
        if [[ "$ACTION" == "$valid" ]]; then
            return 0
        fi
    done
    
    _error "Invalid Rulesets API action: '$ACTION'. Valid actions: ${VALID_ACTIONS[*]}"
    return 1
}

# =====================================
# -- cf_ruleset_validate_profile_json $PROFILE_FILE
# -- Validate a v3 profile JSON file for Rulesets API compatibility
# -- Returns: 0 if valid, 1 if invalid
# =====================================
cf_ruleset_functions["cf_ruleset_validate_profile_json"]="Validate a v3 profile JSON file"
function cf_ruleset_validate_profile_json () {
    local PROFILE_FILE=$1
    local total_errors=0
    
    if [[ ! -f "$PROFILE_FILE" ]]; then
        _error "Profile file not found: $PROFILE_FILE"
        return 1
    fi
    
    _running2 "Validating profile for Rulesets API compatibility: $PROFILE_FILE"
    
    # Check JSON syntax
    if ! jq empty "$PROFILE_FILE" 2>/dev/null; then
        _error "Invalid JSON syntax in $PROFILE_FILE"
        return 1
    fi
    
    # Check for v3 schema (version field)
    local SCHEMA_VERSION
    SCHEMA_VERSION=$(jq -r '.version // 2' "$PROFILE_FILE")
    
    if [[ "$SCHEMA_VERSION" -lt 3 ]]; then
        _warning "Profile uses v$SCHEMA_VERSION schema. Consider upgrading to v3 for full Rulesets API support."
        _warning "v2 profiles use 'priority' field which is not used by the Rulesets API."
    fi
    
    # Validate each rule's action
    local RULE_COUNT
    RULE_COUNT=$(jq '.rules | length' "$PROFILE_FILE")
    
    for ((i=0; i<RULE_COUNT; i++)); do
        local ACTION
        ACTION=$(jq -r ".rules[$i].action" "$PROFILE_FILE")
        
        if ! cf_ruleset_validate_action "$ACTION"; then
            _error "Rule $((i+1)): Invalid action '$ACTION' for Rulesets API"
            ((total_errors++))
        fi
    done
    
    if [[ $total_errors -eq 0 ]]; then
        _success "Profile validation passed for Rulesets API"
        return 0
    else
        _error "Profile validation failed with $total_errors errors"
        return 1
    fi
}

# =============================================================================
# -- CLI Wrapper Functions
# =============================================================================
# These wrappers bridge the CLI command handlers (which receive DOMAIN_NAME +
# ZONE_ID) to the lower-level Rulesets API functions. They handle looking up
# the ruleset_id from the entry point, confirmation prompts, etc.

# =====================================
# -- cf_ruleset_list_rules_action $DOMAIN_NAME $ZONE_ID [$TABLE_ONLY]
# -- CLI wrapper for cf_ruleset_list_rules.
# -- $DOMAIN_NAME is used only for display (compatible with _run_on_zones).
# =====================================
cf_ruleset_functions["cf_ruleset_list_rules_action"]="CLI wrapper: list rules from entry point"
function cf_ruleset_list_rules_action () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local TABLE_ONLY=${3:-0}
    
    _debug "function:${FUNCNAME[0]} - Listing rules for $DOMAIN_NAME / $ZONE_ID"
    
    cf_ruleset_list_rules "$ZONE_ID" "$TABLE_ONLY"
}

# =====================================
# -- cf_ruleset_delete_rule_action $DOMAIN_NAME $ZONE_ID $RULE_ID
# -- Delete a single rule from the entry point ruleset.
# -- Looks up the ruleset_id, then calls cf_ruleset_delete_rule.
# =====================================
cf_ruleset_functions["cf_ruleset_delete_rule_action"]="CLI wrapper: delete a single rule"
function cf_ruleset_delete_rule_action () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local RULE_ID=$3
    
    _running2 "Deleting rule $RULE_ID on ${DOMAIN_NAME}/${ZONE_ID} via Rulesets API"
    
    # Get entry point to find ruleset_id
    if ! cf_ruleset_get_entrypoint "$ZONE_ID"; then
        _error "No entry point ruleset found for $DOMAIN_NAME"
        return 1
    fi
    
    local RULESET_ID
    RULESET_ID=$(echo "$RULESET_API_OUTPUT" | jq -r '.result.id')
    
    # Ask for confirmation (matching old CLI UX)
    read -r -p "Delete rule $RULE_ID from ${DOMAIN_NAME}/${ZONE_ID}? (y/N): " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
        _error "Operation cancelled"
        return 1
    fi
    
    cf_ruleset_delete_rule "$ZONE_ID" "$RULESET_ID" "$RULE_ID"
}

# =====================================
# -- cf_ruleset_delete_rules_action $DOMAIN_NAME $ZONE_ID
# -- Delete all rules from the entry point ruleset by replacing with empty array.
# =====================================
cf_ruleset_functions["cf_ruleset_delete_rules_action"]="CLI wrapper: delete all rules"
function cf_ruleset_delete_rules_action () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    
    _running2 "Deleting all rules on ${DOMAIN_NAME}/${ZONE_ID} via Rulesets API"
    
    # Get entry point
    if ! cf_ruleset_get_entrypoint "$ZONE_ID"; then
        _warning "No entry point ruleset found for $DOMAIN_NAME"
        return 0
    fi
    
    local RULESET_ID
    RULESET_ID=$(echo "$RULESET_API_OUTPUT" | jq -r '.result.id')
    
    # Replace with empty rules array
    cf_ruleset_replace_all_rules "$ZONE_ID" "$RULESET_ID" "[]"
}

# =====================================
# -- cf_ruleset_get_entrypoint_action $DOMAIN_NAME $ZONE_ID
# -- CLI wrapper: get entry point ruleset and print formatted info.
# =====================================
cf_ruleset_functions["cf_ruleset_get_entrypoint_action"]="CLI wrapper: get entry point ruleset"
function cf_ruleset_get_entrypoint_action () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    
    _running2 "Getting entry point ruleset for ${DOMAIN_NAME}/${ZONE_ID}"
    
    if cf_ruleset_get_entrypoint "$ZONE_ID"; then
        # Pretty-print the ruleset summary
        local RULESET_ID RULESET_NAME RULE_COUNT
        RULESET_ID=$(echo "$RULESET_API_OUTPUT" | jq -r '.result.id')
        RULESET_NAME=$(echo "$RULESET_API_OUTPUT" | jq -r '.result.name // "unnamed"')
        RULE_COUNT=$(echo "$RULESET_API_OUTPUT" | jq '.result.rules | length')
        
        echo ""
        echo -e "${CBLUEBG} Entry Point Ruleset for $DOMAIN_NAME ${NC}"
        echo -e "  ${CGRAY}ID:${NC}      $RULESET_ID"
        echo -e "  ${CGRAY}Name:${NC}    $RULESET_NAME"
        echo -e "  ${CGRAY}Rules:${NC}   $RULE_COUNT"
        echo ""
        echo "$RULESET_API_OUTPUT" | jq -r '.result.rules[] | "  \(.id) [\(.action)] \(.description // "(no description)")"'
        echo ""
    else
        _warning "No entry point ruleset found for $DOMAIN_NAME"
    fi
}

# =====================================
# -- cf_ruleset_add_rule_action $DOMAIN_NAME $ZONE_ID $RULE_JSON [$POSITION_JSON]
# -- CLI wrapper: add a single rule to the entry point ruleset.
# =====================================
cf_ruleset_functions["cf_ruleset_add_rule_action"]="CLI wrapper: add a rule to entry point"
function cf_ruleset_add_rule_action () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local RULE_JSON=$3
    local POSITION_JSON=${4:-}
    
    _running2 "Adding rule to entry point on ${DOMAIN_NAME}/${ZONE_ID}"
    
    # Get or create entry point
    local RULESET_ID
    RULESET_ID=$(_cf_ruleset_get_or_create_entrypoint "$ZONE_ID" "[]")
    if [[ -z "$RULESET_ID" ]]; then
        _error "Could not obtain entry point ruleset"
        return 1
    fi
    
    cf_ruleset_add_rule "$ZONE_ID" "$RULESET_ID" "$RULE_JSON" "$POSITION_JSON"
}

# =====================================
# -- cf_ruleset_update_rule_action $DOMAIN_NAME $ZONE_ID $RULE_ID $RULE_JSON
# -- CLI wrapper: update a single rule in the entry point ruleset.
# =====================================
cf_ruleset_functions["cf_ruleset_update_rule_action"]="CLI wrapper: update a rule in entry point"
function cf_ruleset_update_rule_action () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local RULE_ID=$3
    local RULE_JSON=$4
    
    _running2 "Updating rule $RULE_ID on ${DOMAIN_NAME}/${ZONE_ID}"
    
    # Get entry point
    if ! cf_ruleset_get_entrypoint "$ZONE_ID"; then
        _error "No entry point ruleset found for $DOMAIN_NAME"
        return 1
    fi
    
    local RULESET_ID
    RULESET_ID=$(echo "$RULESET_API_OUTPUT" | jq -r '.result.id')
    
    cf_ruleset_update_rule "$ZONE_ID" "$RULESET_ID" "$RULE_ID" "$RULE_JSON"
}

# =============================================================================
# -- Migration Tool
# =============================================================================

# =====================================
# -- cf_ruleset_migrate_existing $DOMAIN_NAME $ZONE_ID [$DELETE_OLD]
# -- Migrate existing Firewall Rules (deprecated API) to the Rulesets API.
# -- Fetches all Firewall Rules + Filters for a zone, converts them to
# -- the Rulesets API format, and applies them to the phase entry point.
# -- If DELETE_OLD=1, also removes the old Firewall Rules and Filters.
# =====================================
cf_ruleset_functions["cf_ruleset_migrate_existing"]="Migrate existing Firewall Rules to Rulesets API"
function cf_ruleset_migrate_existing () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local DELETE_OLD=${3:-0}
    
    _running2 "Migrating existing Firewall Rules to Rulesets API for ${DOMAIN_NAME}/${ZONE_ID}"
    
    # 1. Get existing Firewall Rules via the old API
    # Use _cf_ruleset_api so we can handle errors (cf_api would exit on non-200)
    _cf_ruleset_api GET "/client/v4/zones/${ZONE_ID}/firewall/rules"
    
    if [[ $RULESET_CURL_EXIT_CODE != "200" ]]; then
        _error "Failed to fetch existing Firewall Rules (HTTP $RULESET_CURL_EXIT_CODE)"
        parse_cf_error "$RULESET_API_OUTPUT"
        return 1
    fi
    
    local RULE_COUNT
    RULE_COUNT=$(echo "$RULESET_API_OUTPUT" | jq -r '.result_info.total_count // 0')
    
    if [[ $RULE_COUNT -eq 0 ]]; then
        _warning "No existing Firewall Rules found for $DOMAIN_NAME"
        return 0
    fi
    
    _success "Found $RULE_COUNT existing Firewall Rule(s)"
    
    # Print the rules being migrated
    echo ""
    echo "$RULESET_API_OUTPUT" | jq -r '.result[] | "  \(.id) [\(.action)] \(.description)"'
    echo ""
    
    # 2. Convert old Firewall Rules to Rulesets API format
    local NEW_RULES
    NEW_RULES=$(echo "$RULESET_API_OUTPUT" | jq -c '
        [
            .result[] | {
                description: .description,
                expression: .filter.expression,
                action: (
                    if .action == "allow" then "skip"
                    elif .action == "bypass" then "skip"
                    else .action
                    end
                ),
                enabled: (.paused | not),
                logging: {
                    enabled: (.action != "allow" and .action != "bypass")
                },
                action_parameters: (
                    if .action == "allow" then { "ruleset": "current" }
                    elif .action == "bypass" then { "phases": ["http_request_firewall_managed", "http_ratelimit", "http_request_firewall_custom"] }
                    else {}
                    end
                )
            }
        ]
    ')
    
    # 3. Apply converted rules via Rulesets API
    _running2 "Applying converted rules to the phase entry point..."
    if cf_ruleset_apply_profile "$ZONE_ID" "$NEW_RULES"; then
        _success "Migration completed: $RULE_COUNT rules applied via Rulesets API"
    else
        _error "Migration failed — the Rulesets API may have rejected some rules"
        return 1
    fi
    
    # 4. Optionally delete old Firewall Rules and Filters
    if [[ $DELETE_OLD -eq 1 ]]; then
        _running2 "Deleting old Firewall Rules and Filters..."
        
        local RULE_IDS
        RULE_IDS=$(echo "$RULESET_API_OUTPUT" | jq -r '.result[].id')
        local FILTER_IDS
        FILTER_IDS=$(echo "$RULESET_API_OUTPUT" | jq -r '.result[].filter.id // empty')
        
        for RULE_ID in $RULE_IDS; do
            _running3 "Deleting rule: $RULE_ID"
            # Run in subshell to prevent cf_api's exit on error from killing us
            (cf_delete_rule "$ZONE_ID" "$RULE_ID" 2>/dev/null) || true
        done
        for FILTER_ID in $FILTER_IDS; do
            [[ -z "$FILTER_ID" || "$FILTER_ID" == "null" ]] && continue
            _running3 "Deleting filter: $FILTER_ID"
            (cf_delete_filter "$ZONE_ID" "$FILTER_ID" 2>/dev/null) || true
        done
        _success "Old Firewall Rules and Filters deleted"
    else
        _running2 "Old Firewall Rules preserved. Use --delete-old to remove them after verification."
    fi
}
