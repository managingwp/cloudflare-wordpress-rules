# =============================================================================
# -- cf-inc.sh - v2.1 - Cloudflare Includes
# =============================================================================

# =============================================================================
# -- Variables
# =============================================================================
REQUIRED_APPS=("jq" "column")

# ==================================
# -- Colors
# ==================================
NC=$(tput sgr0)
CRED='\e[0;31m'
CRED=$(tput setaf 1)
CYELLOW=$(tput setaf 3)
CGREEN=$(tput setaf 2)
CBLUEBG=$(tput setab 4)
CCYAN=$(tput setaf 6)
CGRAY=$(tput setaf 7)
CDARKGRAY=$(tput setaf 8)

# =============================================================================
# -- Core Functions
# =============================================================================

# =====================================
# -- messages
# =====================================

_error () { [[ $QUIET == "0" ]] && echo -e "${CRED}** ERROR ** - ${*} ${NC}" >&2; } 
_warning () { [[ $QUIET == "0" ]] && echo -e "${CYELLOW}** WARNING ** - ${*} ${NC}" >&2; }
_success () { [[ $QUIET == "0" ]] && echo -e "${CGREEN}** SUCCESS ** - ${*} ${NC}"; }
_running () { [[ $QUIET == "0" ]] && echo -e "${CBLUEBG}${*}${NC}"; }
_running2 () { [[ $QUIET == "0" ]] && echo -e " * ${CGRAY}${*}${NC}"; }
_running3 () { [[ $QUIET == "0" ]] && echo -e " ** ${CDARKGRAY}${*}${NC}"; }
_creating () { [[ $QUIET == "0" ]] && echo -e "${CGRAY}${*}${NC}"; }
_separator () { [[ $QUIET == "0" ]] && echo -e "${CYELLOWBG}****************${NC}"; }
_dryrun () { [[ $QUIET == "0" ]] && echo -e "${CCYAN}** DRYRUN: ${*$}${NC}"; }
_quiet () { [[ $QUIET == "1" ]] && echo -e "${*}"; }

# =====================================
# -- debug - ( $MESSAGE, $LEVEL)
# =====================================
function _debug () {
    local DEBUG_MSG DEBUG_MSG_OUTPUT PREV_CALLER PREV_CALLER_NAME		
	DEBUG_MSG="${*}"

	# Get previous calling function
	PREV_CALLER=$(caller 1)
	PREV_CALLER_NAME=$(echo "$PREV_CALLER" | awk '{print $2}')

	if [ "$DEBUG" = "1" ]; then
		if [[ $DEBUG_CURL_OUTPUT = "1" ]]; then
			DEBUG_MSG_OUTPUT+="CURL_OUTPUT: $CURL_OUTPUT_GLOBAL"
		fi
		# -- Check if DEBUG_MSG is an array
        if [[ "$(declare -p "$arg" 2>/dev/null)" =~ "declare -a" ]]; then
			DEBUG_MSG_OUTPUT+="Array contents:"
			for item in "${arg[@]}"; do
			    DEBUG_MSG_OUTPUT+="${item}"
			done               
            echo -e "${CCYAN}** DEBUG: ${PREV_CALLER_NAME}: ARRAY: ${DEBUG_MSG_OUTPUT}${NC}" >&2    
		else
		    echo -e "${CCYAN}** DEBUG: ${PREV_CALLER_NAME}: ${DEBUG_MSG}${NC}" >&2
        fi
	fi

	if [[ $DEBUG_FILE == "1" ]]; then
		DEBUG_FILE_PATH="$HOME/cloudflare-cli-debug.log"
		echo -e "${PREV_CALLER_NAME}:${DEBUG_MSG_OUTPUT}" >> "$DEBUG_FILE_PATH"
	fi
}

# =====================================
# -- _debug_json $*
# =====================================
#  Print JSON debug to file
# TODO - Should be removed.
_debug_json () {
    if [ -f $SCRIPT_DIR/.debug ]; then
        echo "${*}" | jq
    fi
}

# =====================================
# =====================================
# -- _pre_flight_check (DEPRECATED)
# -- Use cf_auth_init from cf-inc-auth.sh instead
# =====================================
function _pre_flight_check () {
    _debug "DEPRECATED: _pre_flight_check - Use cf_auth_init from cf-inc-auth.sh instead"
    
    # -- Check required
    _debug "Checking for required apps"
    _check_required_apps

    # -- Check bash
    _debug "Checking for bash version"
    _check_bash
    
    # Note: Authentication is now handled by cf_auth_init()
}

# =====================================
# -- _check_required_apps $REQUIRED_APPS
# -- Check for required apps
# =====================================
function _check_required_apps () {
    for app in "${REQUIRED_APPS[@]}"; do
        if ! command -v $app &> /dev/null; then
            _error "$app could not be found, please install it."
            exit 1
        fi
    done

    _debug "All required apps found."
}

# ===============================================
# -- _check_bash - check version of bash
# ===============================================
function _check_bash () {
	# - Check bash version and _die if not at least 4.0
	if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
		_error "Sorry, you need at least bash 4.0 to run this script. Current version is ${BASH_VERSION}"
        exit 1
	fi
}

# =====================================
# -- json2keyval $JSON
# =====================================
function json2_keyval_array () {
    JSON="$1"
    echo "$JSON" | jq -r '
    .result[] |
    (["Key", "Value"],
    ["----", "-----"],
    (to_entries[] | [.key, (.value | tostring)]) | @tsv),
    "----------------------------"' | awk 'NR==1{print; next} /^$/{print "\n"; next} {print}' | column -t
}

# =====================================
# -- json2_keyval $JSON
# =====================================
function json2_keyval () {
    JSON="$1"
    echo "$JSON" | jq -r '
    def to_table:
        (["Key", "Value"],
        ["----", "-----"],
        (to_entries[] | [.key, (.value | tostring)]) | @tsv);

    if .result | type == "array" then
        .result[] | to_table, ""
    else
        .result | to_table
    end
    ' | awk 'NR==1{print; next} /^$/{print "\n"; next} {print}' | column -t
}

# =============================================================================
# -- Multi-Zone Support Functions
# =============================================================================

# =====================================
# -- _load_zones_file $ZONES_FILE
# -- Read zones from a text file
# -- Returns: Prints zones to stdout (one per line)
# =====================================
function _load_zones_file () {
    local ZONES_FILE="$1"
    
    if [[ -z "$ZONES_FILE" ]]; then
        _error "No zones file specified"
        return 1
    fi
    
    if [[ ! -f "$ZONES_FILE" ]]; then
        _error "Zones file not found: $ZONES_FILE"
        return 1
    fi
    
    _debug "Loading zones from file: $ZONES_FILE"
    
    local count_before=${#DOMAINS[@]}
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Skip comment lines (starting with #)
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Remove inline comments and trim whitespace
        local zone
        zone=$(echo "$line" | sed 's/#.*//' | xargs)
        
        # Skip if empty after processing
        [[ -z "$zone" ]] && continue
        
        DOMAINS+=("$zone")
    done < "$ZONES_FILE"
    
    local count_loaded=$((${#DOMAINS[@]} - count_before))
    _debug "Loaded $count_loaded zone(s) from $ZONES_FILE"
}

# =====================================
# -- _deduplicate_zones $ZONES_ARRAY
# -- Remove duplicate zones from array
# -- Usage: mapfile -t ZONES < <(_deduplicate_zones "${ZONES[@]}")
# =====================================
function _deduplicate_zones () {
    # Deduplicates the global DOMAINS array
    local -A seen
    local -a unique_domains=()
    
    for domain in "${DOMAINS[@]}"; do
        if [[ -z "${seen[$domain]:-}" ]]; then
            seen[$domain]=1
            unique_domains+=("$domain")
        fi
    done
    
    DOMAINS=("${unique_domains[@]}")
    _debug "Deduplicated to ${#DOMAINS[@]} unique zone(s)"
}

# =====================================
# -- _confirm_zones
# -- Display zones and ask for confirmation
# -- Uses global: DOMAINS array, SKIP_CONFIRM flag
# -- Returns: 0 to proceed, 1 to abort
# =====================================
function _confirm_zones () {
    local zone_count=${#DOMAINS[@]}
    
    if [[ $zone_count -eq 0 ]]; then
        _error "No zones specified"
        return 1
    fi
    
    # If skip confirmation flag is set, proceed
    if [[ "${SKIP_CONFIRM:-0}" -eq 1 ]]; then
        _debug "Skipping confirmation (--yes flag)"
        return 0
    fi
    
    echo ""
    echo -e "${CYELLOW}The following ${zone_count} zone(s) will be affected:${NC}"
    
    local display_count=0
    local max_display=10
    
    for zone in "${DOMAINS[@]}"; do
        if [[ $display_count -lt $max_display ]]; then
            echo "  - $zone"
            ((display_count++))
        fi
    done
    
    if [[ $zone_count -gt $max_display ]]; then
        local remaining=$((zone_count - max_display))
        echo "  ... and $remaining more"
    fi
    
    echo ""
    read -p "Continue? [y/N]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        _error "Operation cancelled by user"
        return 1
    fi
}

# =====================================
# -- _run_on_zones $COMMAND [args with $DOMAIN and $ZONE_ID placeholders]
# -- Execute a command on multiple zones from global DOMAINS array
# -- $COMMAND: Function name to execute
# -- Remaining args: Arguments to pass, use \$DOMAIN and \$ZONE_ID as placeholders
# -- Uses global: DOMAINS array, SKIP_CONFIRM flag
# =====================================
function _run_on_zones () {
    local COMMAND="$1"
    shift
    local -a cmd_args=("$@")
    local zone_count=${#DOMAINS[@]}
    local success_count=0
    local fail_count=0
    local -a failed_zones=()
    
    _debug "Running command '$COMMAND' on ${zone_count} zone(s)"
    
    echo ""
    _running "Processing ${zone_count} zone(s)..."
    echo ""
    
    local current=0
    for DOMAIN in "${DOMAINS[@]}"; do
        ((current++))
        
        echo -e "${CCYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CBLUEBG} Zone ${current} of ${zone_count}: ${DOMAIN} ${NC}"
        echo -e "${CCYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # Get zone ID
        local ZONE_ID
        if [[ "$DOMAIN" =~ ^[a-f0-9]{32}$ ]]; then
            # Already a zone ID
            ZONE_ID="$DOMAIN"
            _debug "Using zone ID directly: $ZONE_ID"
        else
            # Look up zone ID from domain
            ZONE_ID=$(_cf_zone_id "$DOMAIN")
            if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
                _error "Could not get zone ID for: $DOMAIN"
                ((fail_count++))
                failed_zones+=("$DOMAIN")
                continue
            fi
        fi
        
        # Build the actual arguments by substituting placeholders
        local -a actual_args=()
        for arg in "${cmd_args[@]}"; do
            # Replace $DOMAIN and $ZONE_ID placeholders
            local expanded_arg="$arg"
            expanded_arg="${expanded_arg//\$DOMAIN/$DOMAIN}"
            expanded_arg="${expanded_arg//\$ZONE_ID/$ZONE_ID}"
            actual_args+=("$expanded_arg")
        done
        
        _debug "Executing: $COMMAND ${actual_args[*]}"
        
        # Execute the command
        if "$COMMAND" "${actual_args[@]}"; then
            ((success_count++))
            _success "Completed: $DOMAIN"
        else
            ((fail_count++))
            failed_zones+=("$DOMAIN")
            _error "Failed: $DOMAIN"
        fi
        
        echo ""
    done
    
    # Summary
    echo -e "${CCYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CBLUEBG} Summary ${NC}"
    echo -e "${CCYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Total zones:  ${zone_count}"
    echo -e "  ${CGREEN}Succeeded:${NC}    ${success_count}"
    echo -e "  ${CRED}Failed:${NC}       ${fail_count}"
    
    if [[ ${#failed_zones[@]} -gt 0 ]]; then
        echo ""
        echo -e "${CRED}Failed zones:${NC}"
        for fz in "${failed_zones[@]}"; do
            echo "  - $fz"
        done
    fi
    
    echo ""
    
    [[ $fail_count -eq 0 ]]
}
