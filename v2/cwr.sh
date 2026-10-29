#!/usr/bin/env bash
# =============================================================================
# cwr.sh — Cloudflare WordPress Rules (v2)
#
# Core WAF and profile commands for a Cloudflare zone, in one file, with all
# human output going through the vendored bash-ui library.
#
#   cwr.sh -d example.com -c create-rules default
#   cwr.sh create-rules default -d example.com
#
# stdout carries data only (list-rules --json/--csv/--raw, print-profile).
# =============================================================================

# ==================================
# -- Variables
# ==================================
SCRIPT_NAME="cwr"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )
VERSION=$(cat "${REPO_DIR}/VERSION")
DEBUG="0"
DRYRUN="0"
QUIET="0"
TABLE_ONLY="0"
LIST_FORMAT="table"
LIST_LONG="0"
LIST_DATA_MODE="0"
export PROFILE_DIR="${PROFILE_DIR:-${CWR_PROFILE_DIR:-${REPO_DIR}/profiles}}"

# ==================================
# -- bash-ui (vendored at the repo root)
# ==================================
# $BASH_UI wins, otherwise the nearest vendor/bash-ui/ui.sh at or above this
# script. The stub keeps cwr.sh usable when the library is missing.
_ui_lib=${BASH_UI:-}
if [[ -z $_ui_lib ]]; then
	_ui_dir=$SCRIPT_DIR
	while [[ $_ui_dir != '/' && $_ui_dir != '.' ]]; do
		if [[ -r $_ui_dir/vendor/bash-ui/ui.sh ]]; then
			_ui_lib=$_ui_dir/vendor/bash-ui/ui.sh
			break
		fi
		_ui_dir=$(dirname "$_ui_dir")
	done
fi
# shellcheck source=/dev/null
if [[ -n $_ui_lib ]]; then
	source "$_ui_lib"
fi
if ! command -v ui_ok >/dev/null 2>&1; then
	ui_ok() { printf 'OK: %s\n' "$*" >&2; }
	ui_warn() { printf 'WARN: %s\n' "$*" >&2; }
	ui_err() { printf 'ERR: %s\n' "$*" >&2; }
	ui_die() { printf 'ERR: %s\n' "$*" >&2; exit "${2:-1}"; }
	ui_step() { printf '> %s\n' "$*" >&2; }
	ui_info() { printf '%s\n' "$*" >&2; }
	ui_section() { printf '== %s ==\n' "$*" >&2; }
	ui_header() { printf '== %s ==\n' "${1:-}" >&2; }
	ui_kv() { printf '  %-14s %s\n' "${1:-}" "${2:-}" >&2; }
	ui_list() { printf '  - %s\n' "$@" >&2; }
	ui_hr() { printf '%s\n' '----------------------------------------' >&2; }
	ui_style() { shift; printf '%s' "$*"; }
	ui_confirm() { if [[ ${UI_YES:-0} == 1 || ${2:-n} == y ]]; then return 0; fi; return 1; }
	ui_debug() { :; }
	ui_summary() { :; }
fi
UI_APP_NAME="cwr"

# ============================================================
# -- Constants and state (folded from inc/cf-inc*.sh)
# ============================================================
API_URL="https://api.cloudflare.com"
DEBUG_CURL_OUTPUT="0"
DEBUG_FILE="${DEBUG_FILE:-0}"
REQUIRED_APPS=("jq" "column")

# -- Authentication state
declare -g CF_AUTH_ACCOUNT=""
declare -g CF_AUTH_TOKEN=""
declare -g CF_AUTH_KEY=""
declare -g CF_AUTH_PROFILE=""
declare -g CF_AUTH_METHOD=""
declare -gA _profile_selection_map=()
declare -g _PROFILE_SELECTION_COUNT=0

# -- Settings: the Challenge Passage values behind --challenge-ttl
declare -A CF_SETTINGS
CF_SETTINGS["security_level"]="Security Level"
CF_SETTINGS["challenge_ttl"]="Challenge TTL"
CF_SETTINGS["browser_check"]="Browser Check"
CF_SETTINGS["always_use_https"]="Always Use HTTPS"
CF_SETTINGS["min_tls_version"]="Minimum TLS Version"
CF_DEFAULTS_CHALLENGE_TTL=(300 900 1800 2700 3600 7200 10800 14400 28800 57600 86400 604800 2592000 31536000)
CF_DEFAULTS_SECURITY_LEVEL=("essentially_off" "low" "medium" "high" "under_attack")
CF_DEFAULTS_BROWSER_CHECK=("on" "off")
CF_DEFAULTS_ALWAYS_USE_HTTPS=("on" "off")
CF_DEFAULTS_MIN_TLS_VERSION=("1.0" "1.1" "1.2" "1.3")

# ============================================================
# -- from inc/cf-inc.sh
# ============================================================
# =====================================
# -- _normalize_domain $DOMAIN
# -- Normalize a domain argument to a bare domain
# -- Strips scheme (http://, https://), path, query, port and leading www.
# -- Accepts: http://www.example.com/path, https://example.com, example.com, zone IDs
# -- Returns: bare lowercase domain (e.g. example.com); empty on invalid input
# =====================================
function _normalize_domain () {
    local DOMAIN_INPUT="${1:-}"
    local DOMAIN_OUTPUT

    # Nothing to normalize
    [[ -z "$DOMAIN_INPUT" ]] && return 1

    # Trim whitespace and lowercase (DNS is case-insensitive)
    DOMAIN_OUTPUT=$(echo "$DOMAIN_INPUT" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Strip scheme (http://, https://, ftp://, etc.)
    DOMAIN_OUTPUT=$(echo "$DOMAIN_OUTPUT" | sed -E 's#^[a-z][a-z0-9+.-]*://##')

    # Strip path, query, fragment, or port (everything from first /, ?, #, or :)
    DOMAIN_OUTPUT=$(echo "$DOMAIN_OUTPUT" | sed -E 's#[/?#:].*$##')

    # Strip leading www. (input is already lowercased)
    DOMAIN_OUTPUT=$(echo "$DOMAIN_OUTPUT" | sed -E 's#^www\.##')

    [[ -z "$DOMAIN_OUTPUT" ]] && return 1

    echo "$DOMAIN_OUTPUT"
}

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

    ui_warn "${zone_count} zone(s) will be affected:"

    local display_count=0
    local max_display=10

    for zone in "${DOMAINS[@]}"; do
        if [[ $display_count -lt $max_display ]]; then
            ui_list "$zone"
        fi
        ((display_count++))
    done

    if [[ $zone_count -gt $max_display ]]; then
        ui_info "... and $((zone_count - max_display)) more"
    fi

    if ui_confirm "Continue?" n; then
        return 0
    fi
    _error "Operation cancelled by user"
    return 1
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
    local data_mode=${LIST_DATA_MODE:-0}

    _debug "Running command '$COMMAND' on ${zone_count} zone(s)"
    
    if [[ $data_mode -ne 1 ]]; then
        ui_step "Processing ${zone_count} zone(s)..."
    fi

    local current=0
    for DOMAIN in "${DOMAINS[@]}"; do
        ((current++))

        if [[ $data_mode -ne 1 ]]; then
            ui_section "Zone ${current} of ${zone_count}: ${DOMAIN}"
        fi
        
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
            if [[ $data_mode -ne 1 ]]; then
                _success "Completed: $DOMAIN"
            fi
        else
            ((fail_count++))
            failed_zones+=("$DOMAIN")
            _error "Failed: $DOMAIN"
        fi
        
        if [[ $data_mode -ne 1 ]]; then
            echo ""
        fi
    done
    
    # Summary
    if [[ $data_mode -ne 1 ]]; then
        ui_section "Summary"
        ui_kv "Total zones" "$zone_count"
        ui_kv "Succeeded" "$success_count"
        ui_kv "Failed" "$fail_count"
        if [[ ${#failed_zones[@]} -gt 0 ]]; then
            ui_warn "Failed zones:"
            ui_list "${failed_zones[@]}"
        fi
    fi

    [[ $fail_count -eq 0 ]]
}

# ============================================================
# -- from inc/cf-inc-api.sh
# ============================================================
function cf_api() {
    # -- Run cf_api with tokens
    _debug "function:${FUNCNAME[0]} - ${*}"

    # -- Pagination
    local PAGINATE=0
    local ALL_PAGES=0
    local PAGE=1
    local PER_PAGE=50
    # shellcheck disable=SC2034
    local HAS_MORE=false
    # shellcheck disable=SC2034
    local COMBINED_RESULTS=""
    local API_PATH=""
    local REQUEST=""
    local CURL_HEADERS=()
    local args=()

    # Parse arguments for pagination options
    for arg in "$@"; do
        case "$arg" in
            --paginate)
                PAGINATE=1
                ;;
            --all-pages)
                PAGINATE=1
                # shellcheck disable=SC2034
                ALL_PAGES=1
                ;;
            --page=*)
                PAGE="${arg#*=}"
                PAGINATE=1
                ;;
            --per-page=*)
                PER_PAGE="${arg#*=}"
                PAGINATE=1
                ;;
            *)
                args+=("$arg")
                ;;
        esac
    done
    _debug "ARG: ${args[*]}"

    # Set pagination parameters
    REQUEST="${args[0]}"
    API_PATH="${args[1]}"
    EXTRA=("${args[@]:2}")

    # Add pagination parameters if needed
    if [[ $PAGINATE -eq 1 ]]; then
        # Check if API_PATH already has query parameters
        if [[ "$API_PATH" == *\?* ]]; then            
            API_PATH="${API_PATH}&page=${PAGE}&per_page=${PER_PAGE}"
        else
            API_PATH="${API_PATH}?page=${PAGE}&per_page=${PER_PAGE}"
        fi
    fi
    _debug "API_PATH: $API_PATH"

    # -- Create headers for curl
    if [[ -n $API_ACCOUNT && -n $API_APIKEY ]]; then
        CURL_HEADERS=("-H" "X-Auth-Key: ${API_APIKEY}" -H "X-Auth-Email: ${API_ACCOUNT}")
        _debug "Using \$API_APIKEY as X-Auth-Key. \$CURL_HEADERS: -H X-Auth-Key: [MASKED] -H X-Auth-Email: ${API_ACCOUNT}"        
    elif [[ -n $API_TOKEN ]]; then
        CURL_HEADERS=("-H" "Authorization: Bearer ${API_TOKEN}")
        _debug "Using \$API_TOKEN as 'Authorization: Bearer'. \$CURL_HEADERS: -H Authorization: Bearer [MASKED]"        
    else
        _error "No API Token or API Key found...major error...exiting"
        exit 1
    fi

    # -- Create temporary file for curl output
    CURL_OUTPUT=$(mktemp)

    # -- Start API Call
    local MASKED_HEADERS
    MASKED_HEADERS=$(printf '%s' "${CURL_HEADERS[*]}" | sed 's/Bearer [^ ]*/Bearer [MASKED]/g; s/X-Auth-Key: [^ ]*/X-Auth-Key: [MASKED]/g')
    _debug "Running curl --request $REQUEST --url ${API_URL}${API_PATH} ${MASKED_HEADERS} --output ${CURL_OUTPUT}"
    [[ $DEBUG == "1" ]] && set -x
    CURL_EXIT_CODE=$(curl -s --output "$CURL_OUTPUT" -w "%{http_code}" --request "$REQUEST" \
        --url "${API_URL}${API_PATH}" \
        "${CURL_HEADERS[@]}" \
        "${EXTRA[@]}")
    [[ $DEBUG == "1" ]] && set +x
    API_OUTPUT=$(<"$CURL_OUTPUT")
    _debug "CURL_EXIT_CODE: $CURL_EXIT_CODE"
    _debug_json "$API_OUTPUT"
    rm "$CURL_OUTPUT"

    # -- Check for more pages
    API_PAGES=$(echo $API_OUTPUT | jq -r '.result_info | select(.total_pages > .page).total_pages')
    if [[ $API_PAGES -gt 1 ]]; then
        _debug "More pages found: $API_PAGES"
    fi

    # -- Check for errors
	if [[ $CURL_EXIT_CODE == "200" ]]; then
	    MESG="Success from API: $CURL_EXIT_CODE"
        _debug "$MESG"
        _debug "$API_OUTPUT"
	else
        MESG="Error from API: $CURL_EXIT_CODE"
        _error "$MESG"
        parse_cf_error "$API_OUTPUT"
        exit 1
    fi
}

parse_cf_error () {
    API_OUTPUT=$1
    _debug "Running parse_cf_error"
    ERROR_CODE=$(echo $API_OUTPUT | jq -r '.errors[0].code')
    ERROR_MESSAGE=$(echo $API_OUTPUT | jq -r '.errors[0].message')
    _error "Error: $ERROR_CODE - $ERROR_MESSAGE"
}

function _debug_json() {
    _debug "function:${FUNCNAME[0]} DEBUG_CURL_OUTPUT=$DEBUG_CURL_OUTPUT"
    if [[ $DEBUG_CURL_OUTPUT == "1" ]]; then
        _debug "******** Outputting JSON ********"
        _debug "${*}"
        _debug "******** Outputting JSON ********"
    else
        _debug "Not outputting JSON, use -DC"
    fi
}

function _cf_zone_id () {
    DOMAIN_NAME=$1
    [[ -z $DOMAIN_NAME ]] && _error "Missing domain name" && exit 1
    _debug "function:${FUNCNAME[0]}"
    _debug "Getting zone_id for ${DOMAIN_NAME}"
    cf_api GET /client/v4/zones?name=${DOMAIN_NAME}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        ZONE_ID=$(echo $API_OUTPUT | jq -r '.result[0].id' )
        if [[ $ZONE_ID != "null" ]]; then
            _debug "Zone ID: $ZONE_ID"
            echo $ZONE_ID
        else
            _debug "Couldn't get ZoneID, using -z to provide ZoneID or give access read:zone access to your token"
            _debug "$MESG - $AP_OUTPUT"
            return 1
        fi
    else
        _debug "Couldn't get ZoneID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        _debug "$MESG - $AP_OUTPUT"
        return 1
    fi
}

# ==========================================
# -- usage_set_settings
# ===========================================
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
# -- _cf_set_settings $CF_ZONEID $SETTING $VALUE
# ==================================================
_cf_set_settings () {
    _debug "function:${FUNCNAME[0]} - ${*}"

	local CF_ZONE_ID=$1 SETTING=$2 VALUE=$3
	_debug "function:${FUNCNAME[0]}"
	_debug "Running _cf_set_settings() with ${*}"

	# -- Check if setting was provided
	if [[ -z "$SETTING" ]]; then
		usage_set_settings
		return 1
	fi

	# -- Normalize setting name (convert dashes to underscores)
	SETTING="${SETTING//-/_}"

	# -- Check if setting is valid
	if ! _cf_check_setting "$SETTING"; then
		return 1
	fi

	# -- If no value provided, show available options
	if [[ -z "$VALUE" ]]; then
		echo "Setting: $SETTING"
		_cf_settings_values "$SETTING"
		return 1
	fi

	_running "Setting $SETTING to $VALUE"
    EXTRA=(-H "Content-Type: application/json" \
     --data 
    '{ "value": "'"$VALUE"'" }')        
	cf_api "PATCH" "/client/v4/zones/${CF_ZONE_ID}/settings/${SETTING}" "${EXTRA[@]}"
	if [[ $CURL_EXIT_CODE == "200" ]]; then
		# Report the change, not the API envelope: the body is noise here.
		local SETTING_LABEL=${CF_SETTINGS[$SETTING]:-$SETTING}
		local DISPLAY_VALUE=$VALUE
		if [[ $SETTING == "challenge_ttl" && "$VALUE" =~ ^[0-9]+$ ]]; then
			DISPLAY_VALUE="$VALUE ($(_convert_seconds "$VALUE"))"
		fi
		_success "${SETTING_LABEL} set to ${DISPLAY_VALUE}"
		return 0
	else		
		return 1
	fi
}

# ==================================================
# -- _cf_check_setting $SETTING
# ==================================================
function _cf_check_setting () {
    local SETTING=${1}
    _debug "function:${FUNCNAME[0]}"
    _debug "Checking $SETTING"
    if [[ " ${!CF_SETTINGS[*]} " == *" ${SETTING} "* ]]; then
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
    if [[ " ${CF_SETTINGS_VALUES[*]} " == *" ${VALUE} "* ]]; then
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

# ==================================================
# -- _cf_prompt_challenge_passage [$ZONE_ID]
# -- Prompt user to change Challenge Passage (challenge_ttl) setting.
# -- If a zone ID is provided, queries and displays the current setting first.
# -- If current setting is already 604800 (7 days), skips without prompting.
# -- Prompt options: y = set to 604800, c = choose custom duration, n = skip.
# -- Returns: selected TTL value (seconds) via stdout, or empty if no change.
# ==================================================
function _cf_prompt_challenge_passage () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local CHOSEN_ZONE_ID="${1:-}"
    local CURRENT_TTL=""
    local HUMAN_TIME=""

    # All user-facing output goes to stderr to avoid polluting captured output
    echo "" >&2

    # If zone ID is provided, query the current challenge_ttl setting
    if [[ -n "$CHOSEN_ZONE_ID" ]]; then
        cf_api "GET" "/client/v4/zones/${CHOSEN_ZONE_ID}/settings/challenge_ttl"
        if [[ $CURL_EXIT_CODE == "200" ]]; then
            CURRENT_TTL=$(echo "$API_OUTPUT" | jq -r '.result.value // empty')
        else
            _debug "Failed to get current challenge_ttl for zone $CHOSEN_ZONE_ID"
        fi
    fi

    # -- Section title and current setting
    ui_section "Challenge Passage"
    ui_info "Controls how long a visitor who passed a challenge can browse before being challenged again."

    if [[ -n "$CURRENT_TTL" ]]; then
        HUMAN_TIME=$(_convert_seconds "$CURRENT_TTL")
        ui_kv "Current" "${CURRENT_TTL}s (${HUMAN_TIME})"
    fi

    # -- If already 604800 (7 days), skip — no change needed
    if [[ "$CURRENT_TTL" == "604800" ]]; then
        ui_ok "Challenge Passage is already ${CURRENT_TTL}s (${HUMAN_TIME}) — skipping"
        return 0
    fi

    # -- Prompt: y = set to 604800, c = choose custom duration, n = skip
    printf '\n[y] Set to 604800 (7d) | [c] Choose a custom duration | [n] Skip [n]: ' >&2
    local reply=""
    read -r -n 1 reply || true
    printf '\n' >&2

    case "$reply" in
        [Yy])
            # Set directly to 604800 (7 days)
            echo "604800"
            return 0
            ;;
        [Cc])
            # Fall through to custom duration menu
            ;;
        *)
            # Return empty — no change
            return 0
            ;;
    esac

    # -- Custom duration menu
    ui_section "Challenge Passage durations"
    local count=0
    {
        printf 'Option\tSeconds\tDuration\n'
        for value in "${CF_DEFAULTS_CHALLENGE_TTL[@]}"; do
            count=$((count + 1))
            printf '%s\t%s\t%s\n' "$count" "$value" "$(_convert_seconds "$value")"
        done
    } | ui_table

    local selection=""
    printf 'Enter option [1-%s]: ' "$count" >&2
    read -r selection || true

    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= count )); then
        local ttl_value="${CF_DEFAULTS_CHALLENGE_TTL[$((selection - 1))]}"
        # Only this echo goes to stdout — captured by the caller
        echo "$ttl_value"
        return 0
    fi

    _error "Invalid option: ${selection:-none}. Skipping Challenge Passage change."
    return 1
}

# ==================================================
# -- _cf_set_challenge_ttl_if_lower $ZONE_ID $DESIRED_TTL
# -- Sets challenge_ttl only if the current value is lower than the desired value.
# -- If current TTL >= desired TTL, does nothing (skips).
# -- Returns: 0 on success or skip, 1 on error.
# ==================================================
function _cf_set_challenge_ttl_if_lower () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local ZONE_ID=$1
    local DESIRED_TTL=$2

    if [[ -z "$ZONE_ID" || -z "$DESIRED_TTL" ]]; then
        _error "Usage: _cf_set_challenge_ttl_if_lower <zone_id> <desired_ttl>"
        return 1
    fi

    # Validate that the desired TTL is one of the allowed values
    if ! _cf_check_setting_value "challenge_ttl" "$DESIRED_TTL"; then
        return 1
    fi

    # Query the current challenge_ttl for this zone
    cf_api "GET" "/client/v4/zones/${ZONE_ID}/settings/challenge_ttl"
    if [[ $CURL_EXIT_CODE != "200" ]]; then
        _debug "Failed to get current challenge_ttl for zone $ZONE_ID"
        _error "Unable to query current Challenge TTL for zone $ZONE_ID; skipping."
        return 1
    fi

    local CURRENT_TTL
    CURRENT_TTL=$(echo "$API_OUTPUT" | jq -r '.result.value // empty')

    if [[ -z "$CURRENT_TTL" ]]; then
        _error "Could not parse current Challenge TTL for zone $ZONE_ID; skipping."
        return 1
    fi

    local HUMAN_CURRENT
    HUMAN_CURRENT=$(_convert_seconds "$CURRENT_TTL")
    local HUMAN_DESIRED
    HUMAN_DESIRED=$(_convert_seconds "$DESIRED_TTL")

    # Compare: only set if current is less than desired
    if [[ "$CURRENT_TTL" -ge "$DESIRED_TTL" ]]; then
        _running "Zone $ZONE_ID: current Challenge TTL ${CURRENT_TTL} (${HUMAN_CURRENT}) >= ${DESIRED_TTL} (${HUMAN_DESIRED}) — no change needed."
        return 0
    fi

    _running "Zone $ZONE_ID: current Challenge TTL ${CURRENT_TTL} (${HUMAN_CURRENT}) < ${DESIRED_TTL} (${HUMAN_DESIRED}) — updating."
    _cf_set_settings "$ZONE_ID" "challenge_ttl" "$DESIRED_TTL"
    return $?
}

# ============================================================
# -- from inc/cf-inc-auth.sh
# ============================================================
# ==================================================
# Load .cloudflare configuration file
# ==================================================
function _cf_load_config() {
    local config_file="${1:-$HOME/.cloudflare}"
    
    if [[ ! -f "$config_file" ]]; then
        _error "Configuration file $config_file not found"
        return 1
    fi
    
    # Source the config file safely
    # Strips inline comments so values like "CF_KEY=abc # note" load as "abc".
    while IFS= read -r line; do
        # Trim leading/trailing whitespace
        line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        # Skip comments and empty lines
        [[ $line =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Remove inline comments (anything after an unescaped #)
        line=$(echo "$line" | sed 's/[[:space:]]*#.*$//')
        # Trim again in case whitespace remains after stripping comment
        line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [[ -z "$line" ]] && continue

        # Split key and value
        local key value
        key=${line%%=*}
        value=${line#*=}

        # Skip lines without '='
        [[ "$key" == "$line" ]] && continue

        # Clean key and value
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | sed 's/^["'"'']*//;s/["'"'']*$//' | xargs)
        
        # Export the variable
        export "$key"="$value"
    done < "$config_file"
}

# ==================================================
# Detect available authentication profiles
# ==================================================
function _cf_detect_profiles() {
    local config_file="${1:-$HOME/.cloudflare}"
    local -a profiles=()
    local profile_pattern="^CF_(ACCOUNT|TOKEN|KEY)_([A-Z0-9_]+)$"
    
    # Get all CF_ variables from the config file and extract profile names
    while IFS='=' read -r var value; do
        # Skip comments and empty lines
        [[ $var =~ ^[[:space:]]*# ]] && continue
        [[ -z "$var" ]] && continue
        
        # Clean up the var name
        var=$(echo "$var" | xargs)
        
        if [[ $var =~ $profile_pattern ]]; then
            local profile="${BASH_REMATCH[2]}"
            # Skip generic CF_ variables
            [[ "$profile" =~ ^(ACCOUNT|TOKEN|KEY)$ ]] && continue
            
            # Add to profiles array if not already present
            if [[ ! " ${profiles[*]} " =~ \ ${profile}\  ]]; then
                profiles+=("$profile")
            fi
        fi
    done < "$config_file"
    
    # Also check for generic credentials (CF_ACCOUNT, CF_KEY, CF_TOKEN)
    local has_generic=0
    while IFS='=' read -r var value; do
        # Skip comments and empty lines
        [[ $var =~ ^[[:space:]]*# ]] && continue
        [[ -z "$var" ]] && continue
        
        # Clean up the var name
        var=$(echo "$var" | xargs)
        
        if [[ "$var" == "CF_ACCOUNT" || "$var" == "CF_KEY" || "$var" == "CF_TOKEN" ]]; then
            has_generic=1
            break
        fi
    done < "$config_file"
    
    if [[ $has_generic -eq 1 ]]; then
        profiles+=("DEFAULT")
    fi
    
    printf '%s\n' "${profiles[@]}"
}

# ==================================================
# Get credentials for a specific profile
# ==================================================
function _cf_get_profile_creds() {
    local profile="$1"
    local config_file="${2:-$HOME/.cloudflare}"
    local -A creds=()
    
    # Read from config file
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ $line =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Remove inline comments and trim
        line=$(echo "$line" | sed 's/[[:space:]]*#.*$//')
        [[ -z "$line" ]] && continue

        # Split key and value on first '='
        var=${line%%=*}
        value=${line#*=}
        [[ "$var" == "$line" ]] && continue

        # Clean up var name
        var=$(echo "$var" | xargs)
        # Clean up value (strip surrounding quotes and whitespace)
        value=$(echo "$value" | sed 's/^["'\'']*//;s/["'\'']*$//' | xargs)
        
        if [[ "$profile" == "DEFAULT" ]]; then
            if [[ "$var" == "CF_ACCOUNT" ]]; then
                creds[account]="$value"
            elif [[ "$var" == "CF_TOKEN" ]]; then
                creds[token]="$value"
            elif [[ "$var" == "CF_KEY" ]]; then
                creds[key]="$value"
            fi
        else
            if [[ "$var" == "CF_ACCOUNT_${profile}" ]]; then
                creds[account]="$value"
            elif [[ "$var" == "CF_TOKEN_${profile}" ]]; then
                creds[token]="$value"
            elif [[ "$var" == "CF_KEY_${profile}" ]]; then
                creds[key]="$value"
            fi
        fi
    done < "$config_file"
    
    # Output in format: account|token|key
    printf '%s|%s|%s\n' "${creds[account]}" "${creds[token]}" "${creds[key]}"
}

# ==================================================
# Validate credentials
# ==================================================
function _cf_validate_creds() {
    local account="$1"
    local token="$2"
    local key="$3"
    
    # Must have either token OR (account + key)
    if [[ -n "$token" ]]; then
        [[ -z "$account" ]] && return 0  # Token-only auth is valid
        return 0
    elif [[ -n "$account" && -n "$key" ]]; then
        return 0
    else
        return 1
    fi
}

# ==================================================
# Format and display profiles (shared by list, select, and quiet)
# ==================================================
function _cf_display_profiles_formatted() {
    local config_file="$1"
    local mode="$2"  # "list", "select", or "quiet"
    local -a profiles
    local -a default_profiles
    local -a other_profiles
    mapfile -t profiles < <(_cf_detect_profiles "$config_file")
    
    if [[ ${#profiles[@]} -eq 0 ]]; then
        return 1
    fi
    
    # Separate DEFAULT profiles from others (DEFAULT goes first)
    for profile in "${profiles[@]}"; do
        if [[ "$profile" == "DEFAULT" ]]; then
            default_profiles+=("$profile")
        else
            other_profiles+=("$profile")
        fi
    done
    
    # Combine arrays with DEFAULT first
    local -a sorted_profiles=("${default_profiles[@]}" "${other_profiles[@]}")
    
    # Quiet mode only populates the map without printing
    local show_output=true
    [[ "$mode" == "quiet" ]] && show_output=false
    
    # Display header
    if $show_output; then
        ui_warn "Multiple Cloudflare profiles found in $config_file"
    fi

    local counter=1
    # Use the global selection map (already declared at top level)
    # Just clear it and repopulate
    for i in "${!_profile_selection_map[@]}"; do unset '_profile_selection_map[$i]'; done

    for profile in "${sorted_profiles[@]}"; do
        local creds
        IFS='|' read -r account token key <<< "$(_cf_get_profile_creds "$profile" "$config_file")"

        local label="$profile"
        if [[ "$profile" == "DEFAULT" ]]; then
            label="Default"
        fi

        # Display and map Account API entries
        if [[ -n "$account" && -n "$key" ]]; then
            if $show_output; then
                ui_kv "$counter. $label" "Account API ($account)"
            fi
            _profile_selection_map[$counter]="${profile}:account"
            ((counter++))
        fi

        # Display and map Token API entries
        if [[ -n "$token" ]]; then
            if $show_output; then
                ui_kv "$counter. $label" "Token API"
            fi
            _profile_selection_map[$counter]="${profile}:token"
            ((counter++))
        fi
    done
    
    if $show_output; then
        ui_info "Enter a number to pick a profile"
    fi
    
    # Store the total count in global variable for caller to use
    _PROFILE_SELECTION_COUNT=$((counter - 1))
}

# ==================================================
# Interactive profile selection
# ==================================================
function _cf_select_profile() {
    local config_file="${1:-$HOME/.cloudflare}"
    local -a profiles
    mapfile -t profiles < <(_cf_detect_profiles "$config_file")
    
    if [[ ${#profiles[@]} -eq 0 ]]; then
        _error "No Cloudflare credentials found in $config_file"
        return 1
    fi
    
    if [[ ${#profiles[@]} -eq 1 ]]; then
        echo "${profiles[0]}"
        return 0
    fi
    
    # Display profiles and get total count
    # The function will populate _PROFILE_SELECTION_COUNT and _profile_selection_map
    _cf_display_profiles_formatted "$config_file" "select"
    local total_entries=$_PROFILE_SELECTION_COUNT
    
    while true; do
        read -p "Select a profile (1-$total_entries): " selection >&2
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 && $selection -le $total_entries ]]; then
            echo "${_profile_selection_map[$selection]}"
            return 0
        else
            echo "Invalid selection. Please choose 1-$total_entries" >&2
        fi
    done
}

# ==================================================
# Initialize Cloudflare authentication
# Usage: cf_auth_init [profile_name]
#   profile_name can be:
#     - Named profile (e.g., "DEFAULT", "FPM", "JTRASK")
#     - Numeric index from profile list (e.g., "1", "2")
#     - Qualified with method (e.g., "DEFAULT:account", "DEFAULT:token")
# ==================================================
function cf_auth_init() {
    local requested_profile="$1"
    local config_file="${2:-$HOME/.cloudflare}"
    
    _debug "Initializing Cloudflare authentication"
    
    # Load configuration
    if ! _cf_load_config "$config_file"; then
        return 1
    fi
    
    local profile=""
    local auth_method=""
    
    # Determine which profile to use
    if [[ -n "$requested_profile" ]]; then
        # Specific profile requested — could be name, number, or qualified name
        profile="$requested_profile"
        _debug "Using requested profile: $profile"
        
        # Numeric selection: look up from the selection map
        if [[ "$profile" =~ ^[0-9]+$ ]]; then
            _cf_display_profiles_formatted "$config_file" "quiet"
            if [[ -z "${_profile_selection_map[$profile]:-}" ]]; then
                _error "Invalid profile selection: $profile"
                return 1
            fi
            profile="${_profile_selection_map[$profile]}"
            _debug "Numeric selection maps to: $profile"
        fi
        
        # Parse method qualifier (e.g., "DEFAULT:account" -> profile="DEFAULT", auth_method="account")
        if [[ "$profile" == *:* ]]; then
            auth_method="${profile##*:}"
            profile="${profile%%:*}"
            _debug "Parsed method qualifier: profile=$profile, method=$auth_method"
        fi
        
        # Normalize profile name to uppercase for case-insensitive matching
        profile="${profile^^}"
        _debug "Normalized profile name: $profile"
    else
        # Auto-detect or select profile interactively
        profile=$(_cf_select_profile "$config_file")
        if [[ $? -ne 0 ]]; then
            return 1
        fi
        _debug "Selected profile: $profile"
        
        # Parse method qualifier from interactive selection too
        if [[ "$profile" == *:* ]]; then
            auth_method="${profile##*:}"
            profile="${profile%%:*}"
            _debug "Parsed method qualifier: profile=$profile, method=$auth_method"
        fi
    fi
    
    # Get credentials for selected profile
    local creds
    IFS='|' read -r account token key <<< "$(_cf_get_profile_creds "$profile" "$config_file")"
    
    # If a specific auth method was requested, use only that credential type
    if [[ "$auth_method" == "account" ]]; then
        token=""  # Clear token to force account/key auth
    elif [[ "$auth_method" == "token" ]]; then
        account=""  # Clear account to force token auth
        key=""
    fi
    
    # Validate credentials
    if ! _cf_validate_creds "$account" "$token" "$key"; then
        _error "Invalid credentials for profile: $profile"
        return 1
    fi
    
    # Set global variables
    CF_AUTH_ACCOUNT="$account"
    CF_AUTH_TOKEN="$token"
    CF_AUTH_KEY="$key"
    CF_AUTH_PROFILE="$profile"
    
    # ==================================================
    # Backwards compatibility - Set legacy variables
    # ==================================================
    export API_ACCOUNT="$account"
    export API_TOKEN="$token"
    export API_APIKEY="$key"
    
    # Determine authentication method
    if [[ -n "$token" ]]; then
        CF_AUTH_METHOD="token"
        if [[ ${LIST_DATA_MODE:-0} -ne 1 ]]; then
            _success "Authenticated using token (profile: $profile)"
        fi
        _debug "Set API_TOKEN for backwards compatibility"
    else
        CF_AUTH_METHOD="key"
        if [[ ${LIST_DATA_MODE:-0} -ne 1 ]]; then
            _success "Authenticated using account/key (profile: $profile, account: $account)"
        fi
        _debug "Set API_ACCOUNT and API_APIKEY for backwards compatibility"
    fi
    
    return 0
}


# ==================================
# -- Include cf-inc files (still folding)
# ==================================
source "$REPO_DIR/inc/cf-inc-wp.sh"
source "$REPO_DIR/inc/cf-inc-rulesets.sh"

# ==================================
# -- Output layer
# ==================================
# inc/cf-inc.sh still defines the v1 message helpers; these definitions win
# because they come after the includes. Every one of them now goes to stderr,
# so stdout stays data-only.
_error() { ui_err "$*"; }
_warning() { ui_warn "$*"; }
_success() { ui_ok "$*"; }
_running() { ui_step "$*"; }
_running2() { ui_info "$*"; }
_running3() { ui_step "$*"; }
_creating() { ui_step "$*"; }
_separator() { ui_hr; }
_dryrun() { ui_info "DRYRUN: $*"; }
_debug() { ui_debug "$*"; }

# ==================================
# -- usage
# ==================================
usage () {
	export UI_KV_WIDTH=30

	ui_header "Cloudflare WordPress Rules" "Manage WAF rules across zones"
	ui_section "Usage"
	ui_list "$SCRIPT_NAME -d <domain> -c <command> [options]" "$SCRIPT_NAME <command> [options] -d <domain>"

	ui_section "Rule commands"
	ui_kv "create-rules <profile>" "Create rules on a zone from a profile"
	ui_kv "update-rules <profile>" "Update rules on a zone from a profile"
	ui_kv "upgrade-default-rules" "Upgrade the MWP default rules on a zone"
	ui_kv "list-rules" "List the zone's WAF custom rules"
	ui_kv "delete-rule <id>" "Delete one rule by ID"
	ui_kv "delete-rules" "Delete every rule on a zone"

	ui_section "Profile commands"
	ui_kv "list-profiles" "List the available rule profiles"
	ui_kv "print-profile <profile>" "Print the rules in a profile"
	ui_kv "validate-profile <profile>" "Validate a profile's JSON and expressions"

	ui_section "Options"
	ui_kv "-d, --domain <domain>" "Zone, or a full URL normalised to one; repeatable"
	ui_kv "-zf, --zones-file <file>" "Read zones from a file, one per line"
	ui_kv "-c, --command <command>" "Command to run (optional with the positional form)"
	ui_kv "-y, --yes" "Skip the multi-zone confirmation prompt"
	ui_kv "--config <file>" "Credentials file instead of \$HOME/.cloudflare"
	ui_kv "--cf-profile <name>" "Named credential profile inside that file"
	ui_kv "--challenge-ttl <seconds>" "Set Challenge Passage at or below this TTL"
	ui_kv "--json | --csv | --raw" "list-rules output: JSON, CSV, or the raw response"
	ui_kv "--long" "list-rules: detailed block per rule"
	ui_kv "--debug" "Verbose diagnostics on stderr"
	ui_kv "--debug-json" "Diagnostics plus JSON bodies on stderr"
	ui_kv "-h, --help" "Show this help and exit"

	ui_section "Examples"
	ui_list "$SCRIPT_NAME -d example.com -c create-rules default" \
		"$SCRIPT_NAME create-rules default -d example.com" \
		"$SCRIPT_NAME -d example.com -c create-rules default --challenge-ttl 3600" \
		"$SCRIPT_NAME -d example.com -c list-rules --json" \
		"$SCRIPT_NAME -d site-a.com -d site-b.com -c create-rules default" \
		"$SCRIPT_NAME -zf zones.txt -c delete-rules -y"

	ui_section "Authentication"
	ui_kv "Credentials" "\$HOME/.cloudflare; see .cloudflare.example"
	ui_kv "Profiles" "CF_TOKEN_PROD, CF_ACCOUNT_DEV/CF_KEY_DEV, and so on"

	ui_kv "Version" "$VERSION"
}

# =============================================================================
# -- main
# =============================================================================

# -- Multi-zone support variables
declare -a DOMAINS=()
ZONES_FILE=""
SKIP_CONFIRM=0
MULTI_ZONE=0
CONFIG_FILE=""
CF_PROFILE=""
CHALLENGE_TTL_ARG=""
declare -a LIST_FORMAT_FLAGS=()
TABLE_ONLY_EXPLICIT=0

# -- Parse options
    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
		-d|--domain)
		# Accumulate multiple -d arguments (full URLs are normalized to bare domain)
		NORM_DOMAIN="$(_normalize_domain "$2")"
		if [[ -z "$NORM_DOMAIN" ]]; then
			_warning "Could not normalize domain: '$2', using as-is"
			NORM_DOMAIN="$2"
		fi
		DOMAINS+=("$NORM_DOMAIN")
		shift # past argument
		shift # past variable
		;;
		-zf|--zones-file)
		ZONES_FILE="$2"
		shift # past argument
		shift # past variable
		;;
		--config)
		CONFIG_FILE="$2"
		shift # past argument
		shift # past variable
		;;
        --cf-profile|--cf-auth-profile)
        CF_PROFILE="$2"
        shift # past argument
        shift # past variable
        ;;
        --challenge-ttl)
        CHALLENGE_TTL_ARG="$2"
        shift # past argument
        shift # past variable
        ;;
		-y|--yes)
		SKIP_CONFIRM=1
		shift # past argument
		;;
		-c|--command)
		CMD="$2"
		shift # past argument
		shift # past variable
		;;
		-h|--help)
		usage
		exit 0
		;;
        --debug)
        # shellcheck disable=SC2034
        DEBUG=1
        UI_VERBOSE=1
        shift # past argument
        ;;
        --debug-json)
        # shellcheck disable=SC2034
        DEBUG=1
        UI_VERBOSE=1
        # shellcheck disable=SC2034
        DEBUG_JSON=1
        shift # past argument
        ;;
        --table-only)
        # Deprecated: the compact table is now the default list-rules output.
        TABLE_ONLY="1"
        TABLE_ONLY_EXPLICIT=1
        shift # past argument
        ;;
        --json|--csv|--raw)
        LIST_FORMAT_FLAGS+=("${key#--}")
        shift # past argument
        ;;
        --long)
        LIST_LONG="1"
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

# -- Resolve the list-rules output format (exactly one format at a time)
if [[ ${#LIST_FORMAT_FLAGS[@]} -gt 1 ]]; then
    _error "Choose only one of --json, --csv or --raw"
    exit 2
fi
if [[ ${#LIST_FORMAT_FLAGS[@]} -eq 1 ]]; then
    LIST_FORMAT="${LIST_FORMAT_FLAGS[0]}"
    if [[ $TABLE_ONLY_EXPLICIT -eq 1 ]]; then
        _error "--table-only cannot be combined with --${LIST_FORMAT}"
        exit 2
    fi
fi
if [[ $LIST_LONG -eq 1 && $LIST_FORMAT != "table" ]]; then
    _error "--long only applies to the table output; drop --${LIST_FORMAT}"
    exit 2
fi

set -- "${POSITIONAL[@]}" # restore positional parameters

# ==================================
# -- Commands
# ==================================
# One list drives the positional form, the whitelist and the help text.
CORE_COMMANDS="create-rules update-rules upgrade-default-rules list-rules delete-rule delete-rules list-profiles print-profile validate-profile"
COMMANDS_NO_AUTH="list-profiles print-profile validate-profile"
COMMANDS_REQUIRING_AUTH="create-rules update-rules upgrade-default-rules list-rules delete-rule delete-rules"

# Positional form: `cwr.sh create-rules default -d example.com`
if [[ -z ${CMD:-} && -n ${1:-} ]]; then
    if [[ " $CORE_COMMANDS " == *" $1 "* ]]; then
        CMD=$1
        shift
    fi
fi

# -- Load zones from file if specified
if [[ -n "$ZONES_FILE" ]]; then
    _load_zones_file "$ZONES_FILE"
fi

# -- For backward compatibility, set DOMAIN to first zone if only one
if [[ ${#DOMAINS[@]} -eq 1 ]]; then
    DOMAIN="${DOMAINS[0]}"
fi

# -- Commands
_debug "ARGS: ${*}@"

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

# -- Validate command and required arguments before authentication
if [[ ! " $CORE_COMMANDS " == *" ${CMD} "* ]]; then
    usage
    _error "Unknown command: $CMD"
    exit 1
fi

# ==================================
# -- list-rules: stdout carries data only, diagnostics stay on stderr
# ==================================
if [[ "$CMD" == "list-rules" ]]; then
    LIST_DATA_MODE=1
fi

# -- Argument validation
if [[ $CMD == "create-rules" || $CMD == "update-rules" ]]; then
    if [[ -z ${1:-} ]]; then
        _error "No profile provided"
        cf_list_profiles
        exit 1
    fi
elif [[ $CMD == "print-profile" || $CMD == "validate-profile" ]]; then
    if [[ -z ${1:-} ]]; then
        _error "No profile provided"
        cf_list_profiles
        exit 1
    fi
elif [[ $CMD == "delete-rule" ]]; then
    if [[ -z ${1:-} ]]; then
        _error "No rule ID provided"
        exit 1
    fi
fi

# -- Check if domain is required for this command
COMMANDS_REQUIRING_DOMAIN="create-rules update-rules upgrade-default-rules list-rules delete-rules delete-rule"

# -- Commands that support multi-zone operations
COMMANDS_SUPPORTING_MULTIZONE="create-rules update-rules list-rules delete-rules"

if [[ " $COMMANDS_REQUIRING_DOMAIN " == *" ${CMD} "* ]]; then
    # Check if we have at least one domain
    if [[ ${#DOMAINS[@]} -eq 0 ]]; then
        usage
        _error "Command '$CMD' requires at least one domain to be specified with -d or -zf"
        exit 1
    fi

    # Deduplicate zones
    _deduplicate_zones

    # For multi-zone operations
    MULTI_ZONE=0
    if [[ ${#DOMAINS[@]} -gt 1 ]]; then
        # Check if command supports multi-zone
        if [[ " $COMMANDS_SUPPORTING_MULTIZONE " != *" ${CMD} "* ]]; then
            _error "Command '$CMD' does not support multiple zones. Please specify a single domain with -d"
            exit 1
        fi
        MULTI_ZONE=1

        # list-rules is read-only and data-only: no confirmation prose on stdout.
        if [[ $LIST_DATA_MODE -ne 1 ]]; then
            # Confirm with user unless -y flag was used
            if ! _confirm_zones; then
                exit 1
            fi
        fi
    fi
fi

# ==================================
# -- Commands that don't need authentication
# ==================================
if [[ $CMD == "list-profiles" ]]; then
    cf_list_profiles
    exit 0
elif [[ $CMD == "print-profile" ]]; then
    PROFILE=$1
    if [[ -z $PROFILE ]]; then
        _error "No profile provided"
        cf_list_profiles
        exit 1
    fi
    cf_print_profile "$PROFILE"
    exit $?
elif [[ $CMD == "validate-profile" ]]; then
    PROFILE=$1
    if [[ -z $PROFILE ]]; then
        _error "No profile provided"
        cf_list_profiles
        exit 1
    fi
    cf_validate_profile "$PROFILE"
    exit $?
fi

# ==================================
# -- Initialize Authentication (for commands that need it)
# ==================================
# Use default config file if not specified
if [[ -z "$CONFIG_FILE" ]]; then
    CONFIG_FILE="$HOME/.cloudflare"
fi

REQUESTED_CF_PROFILE="${CF_PROFILE:-${CF_AUTH_PROFILE:-}}"
if ! cf_auth_init "$REQUESTED_CF_PROFILE" "$CONFIG_FILE"; then
    _error "Authentication failed"
    exit 1
fi

# For single zone, resolve zone ID now (backward compatibility)
if [[ " $COMMANDS_REQUIRING_DOMAIN " == *" ${CMD} "* && $MULTI_ZONE -eq 0 ]]; then
    DOMAIN="${DOMAINS[0]}"
    ZONE_ID=$(_cf_zone_id "$DOMAIN")
    if [[ -z $ZONE_ID ]]; then
        _error "No zone ID found for $DOMAIN"
        exit 1
    else
        if [[ $LIST_DATA_MODE -ne 1 ]]; then
            _running2 "Zone ID found: $ZONE_ID"
        fi
    fi
fi

if [[ $LIST_DATA_MODE -ne 1 ]]; then
    if [[ $MULTI_ZONE -eq 1 ]]; then
        _running "Running $CMD on ${#DOMAINS[@]} zones"
    else
        _running "Running $CMD on $DOMAIN with ID $ZONE_ID"
    fi
fi

# =====================================
# -- _cf_create_rules_with_ttl $DOMAIN $ZONE_ID $PROFILE [$CHALLENGE_TTL]
# -- Combined operation: optionally set challenge TTL (if provided), then create rules.
# -- Returns 0 if both (or the one that runs) succeed. Fails fast on TTL failure.
# =====================================
function _cf_create_rules_with_ttl () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local PROFILE_NAME=$3
    local CHALLENGE_TTL=${4:-}

    # If a challenge TTL was provided, set it (if-lower logic — skips if current >= desired)
    if [[ -n "$CHALLENGE_TTL" ]]; then
        _cf_set_challenge_ttl_if_lower "$ZONE_ID" "$CHALLENGE_TTL" || return 1
    fi

    # Create rules via profile
    cf_profile_create "$DOMAIN_NAME" "$ZONE_ID" "$PROFILE_NAME"
}

# =====================================
# -- create-rules
# =====================================
if [[ $CMD == "create-rules" ]]; then
    PROFILE=$1
    if [[ -z $PROFILE ]]; then
        _error "No profile provided"
        cf_list_profiles
        exit 1
    fi

    # -- Handle Challenge Passage setting
    # If --challenge-ttl was passed, apply it directly (bypasses interaction).
    # Otherwise, prompt interactively (existing behavior).
    if [[ -n "$CHALLENGE_TTL_ARG" ]]; then
        # --challenge-ttl path: single pass per zone — set TTL then create rules
        if [[ $MULTI_ZONE -eq 1 ]]; then
            _run_on_zones _cf_create_rules_with_ttl "\$DOMAIN" "\$ZONE_ID" "$PROFILE" "$CHALLENGE_TTL_ARG"
        else
            _cf_create_rules_with_ttl "$DOMAIN" "$ZONE_ID" "$PROFILE" "$CHALLENGE_TTL_ARG"
        fi
    else
        # -- Prompt for Challenge Passage setting (once, before zone iteration)
        # Pass a zone ID to query the current setting — for single zone it's already
        # resolved; for multi-zone we resolve the first domain to show the info.
        if [[ $MULTI_ZONE -eq 1 ]]; then
            FIRST_ZONE_ID=$(_cf_zone_id "${DOMAINS[0]}")
            CHOSEN_TTL=$(_cf_prompt_challenge_passage "$FIRST_ZONE_ID")
        else
            CHOSEN_TTL=$(_cf_prompt_challenge_passage "$ZONE_ID")
        fi
        if [[ -n "$CHOSEN_TTL" ]]; then
            if [[ $MULTI_ZONE -eq 1 ]]; then
                _run_on_zones _cf_create_rules_with_ttl "\$DOMAIN" "\$ZONE_ID" "$PROFILE" "$CHOSEN_TTL"
            else
                _cf_create_rules_with_ttl "$DOMAIN" "$ZONE_ID" "$PROFILE" "$CHOSEN_TTL"
            fi
        else
            if [[ $MULTI_ZONE -eq 1 ]]; then
                _run_on_zones cf_profile_create "\$DOMAIN" "\$ZONE_ID" "$PROFILE"
            else
                cf_profile_create "$DOMAIN" "$ZONE_ID" "$PROFILE"
            fi
        fi
    fi
# =====================================
# -- update-rules
# =====================================
elif [[ $CMD == "update-rules" ]]; then
    PROFILE=$1
    if [[ -z $PROFILE ]]; then
        _error "No profile provided"
		cf_list_profiles    
        exit 1
    fi
    if [[ $MULTI_ZONE -eq 1 ]]; then
        _run_on_zones cf_update_rules "\$DOMAIN" "\$ZONE_ID" "$PROFILE"
    else
        cf_update_rules "$DOMAIN" "$ZONE_ID" "$PROFILE"
    fi
# =====================================
# -- upgrade-default-rules
# =====================================
elif [[ $CMD == "upgrade-default-rules" ]]; then
    PROFILE="default"
    cf_upgrade_rules_default "$DOMAIN" "$ZONE_ID" "$PROFILE"

# =====================================
# -- list-rules (Rulesets API)
# =====================================
elif [[ $CMD == "list-rules" ]]; then
    if [[ $MULTI_ZONE -eq 1 ]]; then
        _run_on_zones cf_ruleset_list_rules_action "\$DOMAIN" "\$ZONE_ID"
    else
        cf_ruleset_list_rules_action "$DOMAIN" "$ZONE_ID"
    fi
# =====================================
# -- delete-rules (Rulesets API)
# =====================================
elif [[ $CMD == "delete-rules" ]]; then
    if [[ $MULTI_ZONE -eq 1 ]]; then
        _run_on_zones cf_ruleset_delete_rules_action "\$DOMAIN" "\$ZONE_ID"
    else
        cf_ruleset_delete_rules_action "$DOMAIN" "$ZONE_ID"
    fi
# =====================================
# -- delete-rule (Rulesets API)
# =====================================
elif [[ $CMD == "delete-rule" ]]; then
    RULE_ID=$1
	[[ $RULE_ID == "" ]] && _error "No rule ID provided" && exit 1
	cf_ruleset_delete_rule_action "$DOMAIN" "$ZONE_ID" "$RULE_ID"
else
    usage
    _error "No command provided"
    exit 1
fi
