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
# shellcheck disable=SC2034  # read by ui_header inside vendor/bash-ui/ui.sh
UI_APP_NAME="cwr"

# ============================================================
# -- Constants and state (folded from inc/cf-inc*.sh)
# ============================================================
API_URL="https://api.cloudflare.com"
DEBUG_CURL_OUTPUT="0"
DEBUG_FILE="${DEBUG_FILE:-0}"
# -- Authentication state
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
# The value lists are read through eval in _cf_check_setting_value.
# shellcheck disable=SC2034
CF_DEFAULTS_SECURITY_LEVEL=("essentially_off" "low" "medium" "high" "under_attack")
# shellcheck disable=SC2034
CF_DEFAULTS_BROWSER_CHECK=("on" "off")
# shellcheck disable=SC2034
CF_DEFAULTS_ALWAYS_USE_HTTPS=("on" "off")
# shellcheck disable=SC2034
CF_DEFAULTS_MIN_TLS_VERSION=("1.0" "1.1" "1.2" "1.3")

# ============================================================
# -- Helpers: domain normalisation, zone loading and multi-zone runs
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
# -- Cloudflare API, settings and Challenge TTL
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
		_error "No setting given"
		return 1
	fi

	# -- Normalize setting name (convert dashes to underscores)
	SETTING="${SETTING//-/_}"

	# -- Check if setting is valid
	if ! _cf_check_setting "$SETTING"; then
		return 1
	fi

	# -- If no value provided, say so
	if [[ -z "$VALUE" ]]; then
		_error "$SETTING needs a value"
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
# -- Configuration and authentication
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
    
    # Set the credentials cf_api reads
    API_ACCOUNT="$account"
    API_TOKEN="$token"
    API_APIKEY="$key"

    # Determine authentication method
    if [[ -n "$token" ]]; then
        if [[ ${LIST_DATA_MODE:-0} -ne 1 ]]; then
            _success "Authenticated using token (profile: $profile)"
        fi
        _debug "Using API_TOKEN"
    else
        if [[ ${LIST_DATA_MODE:-0} -ne 1 ]]; then
            _success "Authenticated using account/key (profile: $profile, account: $account)"
        fi
        _debug "Using API_ACCOUNT and API_APIKEY"
    fi
    
    return 0
}


# ============================================================
# -- Profiles and applying them to a zone
# ============================================================
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

# =====================================
# -- _cf_profile_path $SELECTOR
# -- Resolve a profile selector to a JSON file path.
# -- Resolution order:
# --   1. Exact filename: $PROFILE_DIR/<selector>.json
# --   2. Internal name: first file whose .name == <selector>
# -- Prints the resolved path on success; returns 1 when nothing matches.
# =====================================
_cf_profile_path () {
    local SELECTOR=$1
    local DIRECT="$PROFILE_DIR/$SELECTOR.json"

    if [[ -f "$DIRECT" ]]; then
        printf '%s\n' "$DIRECT"
        return 0
    fi

    local FILE NAME
    for FILE in "$PROFILE_DIR"/*.json; do
        [[ -e "$FILE" ]] || continue
        NAME=$(jq -r '.name // empty' "$FILE" 2>/dev/null)
        if [[ "$NAME" == "$SELECTOR" ]]; then
            printf '%s\n' "$FILE"
            return 0
        fi
    done

    return 1
}

# =====================================
# -- _cf_profile_display_name $FILE
# -- Name to show for a profile in listings:
# --   * symlink   → the symlink's basename (default.json → default)
# --   * otherwise → the profile's .name (fallback: basename)
# =====================================
_cf_profile_display_name () {
    local FILE=$1

    if [[ -L "$FILE" ]]; then
        basename "$FILE" .json
        return 0
    fi

    local NAME
    NAME=$(jq -r '.name // empty' "$FILE" 2>/dev/null)
    printf '%s\n' "${NAME:-$(basename "$FILE" .json)}"
}

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

    local PROFILE_FILE
    PROFILE_FILE=$(_cf_profile_path "$PROFILE_NAME") || {
        _error "Profile not found: $PROFILE_NAME"
        exit 1
    }

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

    local PROFILE_FILE
    PROFILE_FILE=$(_cf_profile_path "$PROFILE_NAME") || {
        _error "Profile not found: $PROFILE_NAME"
        return 1
    }

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
    local PROFILE_FILE

    _running2 "Upgrading rules on $OBJECT"

    # -- Validate profile
    [[ ! -d $PROFILE_DIR ]] && _error "$PROFILE_DIR doesn't exist, failing" && exit 1
    PROFILE_FILE=$(_cf_profile_path "$PROFILE_NAME")
    [[ -z "$PROFILE_FILE" ]] && _error "Profile not found: $PROFILE_NAME" && return 1

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

# =====================================
# -- cf_list_profiles
# -- List profiles
# =====================================
cf_list_profiles () {
	# -- Check if profile dir exists
	if [[ ! -d $PROFILE_DIR ]]; then
		_error "$PROFILE_DIR doesn't exist, failing"
		exit 1
	fi

	# -- List profiles; each file has a root json name and description
	local i=1
	{
		printf '#\tFile\tName\tDescription\n'
		for FILE in "$PROFILE_DIR"/*.json; do
			_debug "Processing file: $FILE"
			printf '%s\t%s\t%s\t%s\n' \
				"$i" \
				"$(basename "$FILE")" \
				"$(_cf_profile_display_name "$FILE")" \
				"$(jq -r '.description' "$FILE")"
			i=$((i+1))
		done
	} | ui_table
}

# =====================================
# -- cf_print_profile $PROFILE_NAME
# -- Print rules from profile (supports v2 and v3 schemas)
# =====================================
function cf_print_profile () {
    PROFILE_NAME=$1
    PROFILE_FILE=$(_cf_profile_path "$PROFILE_NAME")
    if [[ -z "$PROFILE_FILE" ]]; then
        _error "Profile not found: $PROFILE_NAME"
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
    
    printf '\n'
    printf 'Profile: %s\n' "$PROFILE_NAME"
    printf '  Schema:      v%s\n' "$SCHEMA_VERSION"
    printf '  Phase:       %s\n' "$PHASE"
    printf '  Rules:       %s\n' "$RULE_COUNT"
    printf '\n'
    
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
        STATUS_LINE="Rule $((i+1)): ${DESCRIPTION} (Action: ${ACTION}"
        
        # Priority only for v2
        if [[ "$SCHEMA_VERSION" -lt 3 ]]; then
            local PRIORITY
            PRIORITY=$(jq -r ".rules[$i].priority // \"\"" "$PROFILE_FILE")
            if [[ -n "$PRIORITY" ]]; then
                STATUS_LINE+=", Priority: ${PRIORITY}"
            fi
        fi
        
        # Enabled status
        if [[ "$ENABLED" == "true" ]]; then
            STATUS_LINE+=", Enabled"
        else
            STATUS_LINE+=", Disabled"
        fi
        STATUS_LINE+=")"
        
        printf '%s\n' "$STATUS_LINE"
        
        # Logging (v3)
        if [[ "$SCHEMA_VERSION" -ge 3 ]]; then
            local LOGGING_ENABLED
            LOGGING_ENABLED=$(jq -r ".rules[$i].logging.enabled // true" "$PROFILE_FILE")
            if [[ "$LOGGING_ENABLED" == "false" ]]; then
                printf '  Logging: Disabled\n'
            fi
        fi
        
        # Action parameters (v3)
        if [[ "$SCHEMA_VERSION" -ge 3 ]]; then
            local HAS_AP
            HAS_AP=$(jq ".rules[$i].action_parameters // {} | length" "$PROFILE_FILE")
            if [[ "$HAS_AP" -gt 0 ]]; then
                printf '  Action Parameters:\n'
                jq -r ".rules[$i].action_parameters" "$PROFILE_FILE" | while IFS= read -r line; do
                    printf '    %s\n' "$line"
                done
            fi
        fi
        
        # Expression
        printf 'Expression:\n'
        printf '%s\n' "$EXPRESSION" | while IFS= read -r line; do
            printf '  %s\n' "$line"
        done
        
        printf '%s\n' "$(printf '=%.0s' {1..80})"
    done
}

# =====================================
# -- cf_validate_profile $PROFILE_NAME
# -- Validate a JSON profile file for syntax and structure errors
# =====================================
cf_validate_profile() {
    local PROFILE_NAME=$1
    local PROFILE_FILE
    local total_errors=0
    
    if [[ -z "$PROFILE_NAME" ]]; then
        _error "No profile name provided"
        return 1
    fi
    
    _running2 "Validating profile: $PROFILE_NAME"
    
    # Resolve profile (by filename or internal .name)
    PROFILE_FILE=$(_cf_profile_path "$PROFILE_NAME")
    if [[ -z "$PROFILE_FILE" ]]; then
        _error "Profile not found: $PROFILE_NAME"
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
        _success "Profile validation passed: $PROFILE_NAME"

        # Profile summary stays on stderr: stdout carries data only
        local description
        description=$(jq -r '.description' "$PROFILE_FILE")
        ui_section "Profile summary"
        ui_kv "Name" "$PROFILE_NAME"
        ui_kv "Description" "$description"
        ui_kv "Rules" "$rule_count"

        return 0
    else
        _error "Profile validation failed with $total_errors error(s): $PROFILE_NAME"
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

# ============================================================
# -- Rulesets API: entry points, rule payloads and rendering
# ============================================================
function cf_ruleset_phase_name () {
    echo "http_request_firewall_custom"
}

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

function cf_ruleset_create_entrypoint () {
    local ZONE_ID=$1
    local RULES_JSON=$2
    local NAME=${3:-"Cloudflare WordPress Rules"}
    local PHASE
    PHASE=$(cf_ruleset_phase_name)
    
    _debug "function:${FUNCNAME[0]} - Creating entry point ruleset '$NAME' for phase $PHASE on zone $ZONE_ID"
    
    # Add explicit position indexes to enforce correct evaluation order
    local RULES_JSON_WITH_POS
    RULES_JSON_WITH_POS=$(_cf_ruleset_add_positions "$RULES_JSON")
    _debug "Rules with positions: $RULES_JSON_WITH_POS"
    
    # Build the POST body
    local POST_DATA
    POST_DATA=$(jq -n \
        --arg name "$NAME" \
        --arg kind "zone" \
        --arg phase "$PHASE" \
        --argjson rules "$RULES_JSON_WITH_POS" \
        '{
            name: $name,
            kind: $kind,
            phase: $phase,
            rules: $rules
        }')
    
    _debug_json "$POST_DATA"
    
    _cf_ruleset_api POST "/client/v4/zones/${ZONE_ID}/rulesets" \
        -H "Content-Type: application/json" \
        -d "$POST_DATA"
    
    if [[ $RULESET_CURL_EXIT_CODE == "200" ]]; then
        local RULE_COUNT
        CF_CREATED_RULESET_JSON=$RULESET_API_OUTPUT
        CF_CREATED_RULESET_ID=$(printf '%s' "$RULESET_API_OUTPUT" | jq -r '.result.id // empty')
        RULE_COUNT=$(printf '%s' "$RULESET_API_OUTPUT" | jq -r '(.result.rules // []) | length')
        _success "Created entry point ruleset $CF_CREATED_RULESET_ID with ${RULE_COUNT} rule(s)"
        return 0
    else
        _error "Failed to create entry point ruleset (HTTP $RULESET_CURL_EXIT_CODE)"
        parse_cf_error "$RULESET_API_OUTPUT"
        return 1
    fi
}

function _cf_ruleset_add_positions () {
    local RULES_JSON=$1
    echo "$RULES_JSON" | jq -c '
        [to_entries[] | .value + {position: {index: .key}}]
    '
}

function cf_ruleset_replace_all_rules () {
    local ZONE_ID=$1
    local RULESET_ID=$2
    local RULES_JSON=$3
    
    _debug "function:${FUNCNAME[0]} - Replacing all rules in ruleset $RULESET_ID on zone $ZONE_ID"
    
    # Add explicit position indexes to enforce correct evaluation order
    local RULES_JSON_WITH_POS
    RULES_JSON_WITH_POS=$(_cf_ruleset_add_positions "$RULES_JSON")
    _debug "Rules with positions: $RULES_JSON_WITH_POS"
    
    local PUT_DATA
    PUT_DATA=$(jq -n \
        --argjson rules "$RULES_JSON_WITH_POS" \
        '{rules: $rules}')
    
    _debug_json "$PUT_DATA"
    
    _cf_ruleset_api PUT "/client/v4/zones/${ZONE_ID}/rulesets/${RULESET_ID}" \
        -H "Content-Type: application/json" \
        -d "$PUT_DATA"
    
    if [[ $RULESET_CURL_EXIT_CODE == "200" ]]; then
        local RULE_COUNT
        RULE_COUNT=$(printf '%s' "$RULESET_API_OUTPUT" | jq -r '(.result.rules // []) | length')
        _success "Replaced ${RULE_COUNT} rule(s) in ruleset $RULESET_ID"
        return 0
    else
        _error "Failed to replace rules in ruleset $RULESET_ID (HTTP $RULESET_CURL_EXIT_CODE)"
        parse_cf_error "$RULESET_API_OUTPUT"
        return 1
    fi
}

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

function _cf_ruleset_render_list () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local FORMAT=${LIST_FORMAT:-table}
    local LONG=${LIST_LONG:-0}
    local RESPONSE=${RULESET_API_OUTPUT:-}

    if ! printf '%s' "$RESPONSE" | jq -e . >/dev/null 2>&1; then
        _error "Could not parse the ruleset response for ${DOMAIN_NAME}"
        return 1
    fi

    case "$FORMAT" in
        raw)
            # The unmodified API body, exactly as Cloudflare returned it.
            printf '%s\n' "$RESPONSE"
            ;;
        json)
            # One compact object per zone so multi-zone output is NDJSON.
            printf '%s' "$RESPONSE" | jq -c \
                --arg domain "$DOMAIN_NAME" \
                --arg zone_id "$ZONE_ID" \
                '{
                    domain: $domain,
                    zone_id: $zone_id,
                    ruleset: (if .result then {
                        id: .result.id,
                        name: .result.name,
                        phase: .result.phase,
                        version: .result.version,
                        last_updated: .result.last_updated,
                        rule_count: ((.result.rules // []) | length)
                    } else null end),
                    rules: (.result.rules // [])
                }'
            ;;
        csv)
            _cf_ruleset_render_csv "$DOMAIN_NAME" "$ZONE_ID"
            ;;
        table)
            if [[ $LONG -eq 1 ]]; then
                _cf_ruleset_render_long "$DOMAIN_NAME" "$ZONE_ID" >&2
            else
                _cf_ruleset_render_table "$DOMAIN_NAME" "$ZONE_ID" >&2
            fi
            ;;
        *)
            _error "Unknown list-rules output format: $FORMAT"
            return 1
            ;;
    esac
}

# =====================================
# -- _cf_ruleset_render_table $DOMAIN_NAME $ZONE_ID [$RESPONSE_JSON]
# -- Compact aligned table: #, ACTION, ENABLED, RULE ID, UPDATED, DESCRIPTION.
# -- RESPONSE_JSON defaults to the RULESET_API_OUTPUT global; pass it explicitly
# -- when the caller holds a body that is no longer in the global.
# -- An empty DOMAIN_NAME makes the header name the zone instead.
# =====================================
function _cf_ruleset_render_table () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local RESPONSE=${3:-${RULESET_API_OUTPUT:-}}
    local RULE_COUNT
    RULE_COUNT=$(printf '%s' "$RESPONSE" | jq -r '(.result.rules // []) | length' 2>/dev/null)
    RULE_COUNT=${RULE_COUNT:-0}

    if [[ "$RULE_COUNT" -eq 0 ]]; then
        printf 'No WAF custom rules: %s (%s entry point empty or not created)\n' \
            "${DOMAIN_NAME:-$ZONE_ID}" "$(cf_ruleset_phase_name)"
        return 0
    fi

    if [[ -n "$DOMAIN_NAME" ]]; then
        printf '%s · %s\n' "$DOMAIN_NAME" "$ZONE_ID"
    else
        printf 'zone %s\n' "$ZONE_ID"
    fi
    printf '%s' "$RESPONSE" | jq -r '
        def human_date:
            if . == null or . == "" then "?"
            else (sub("\\.[0-9]+Z$"; "Z") | sub("T"; " ") | sub("Z$"; ""))
            end;
        "\(.result.name // "default") · \(.result.phase // "") · \(((.result.rules // []) | length)) rules · version \(.result.version // "?") · updated \(.result.last_updated | human_date)"
    '
    printf '\n'

    {
        printf '#\tACTION\tENABLED\tRULE ID\tUPDATED\tDESCRIPTION\n'
        printf '%s' "$RESPONSE" | jq -r '
            def human_date:
                if . == null or . == "" then "?"
                else (sub("\\.[0-9]+Z$"; "Z") | sub("T"; " ") | sub("Z$"; ""))
                end;
            (.result.rules // []) | to_entries[] | [
                ((.key + 1) | tostring),
                (.value.action // "?"),
                (if .value.enabled == false then "no" else "yes" end),
                (.value.id // ""),
                (.value.last_updated | human_date),
                (.value.description // "(no description)")
            ] | @tsv
        '
    } | ui_table
}

# =====================================
# -- _cf_ruleset_render_long $DOMAIN_NAME $ZONE_ID [$RESPONSE_JSON]
# -- Detail block per rule: id, enabled, logging, updated, parameters,
# -- expression. RESPONSE_JSON defaults to the RULESET_API_OUTPUT global.
# =====================================
function _cf_ruleset_render_long () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local RESPONSE=${3:-${RULESET_API_OUTPUT:-}}
    local RULE_COUNT
    RULE_COUNT=$(printf '%s' "$RESPONSE" | jq -r '(.result.rules // []) | length' 2>/dev/null)
    RULE_COUNT=${RULE_COUNT:-0}

    if [[ "$RULE_COUNT" -eq 0 ]]; then
        printf 'No WAF custom rules: %s (%s entry point empty or not created)\n' \
            "${DOMAIN_NAME:-$ZONE_ID}" "$(cf_ruleset_phase_name)"
        return 0
    fi

    if [[ -n "$DOMAIN_NAME" ]]; then
        printf '%s · %s\n' "$DOMAIN_NAME" "$ZONE_ID"
    else
        printf 'zone %s\n' "$ZONE_ID"
    fi
    printf '%s' "$RESPONSE" | jq -r '
        def human_date:
            if . == null or . == "" then "?"
            else (sub("\\.[0-9]+Z$"; "Z") | sub("T"; " ") | sub("Z$"; ""))
            end;
        "\(.result.name // "default") · \(.result.phase // "") · \(((.result.rules // []) | length)) rules · version \(.result.version // "?") · updated \(.result.last_updated | human_date)"
    '
    printf '\n'

    printf '%s' "$RESPONSE" | jq -r '
        def human_date:
            if . == null or . == "" then "?"
            else (sub("\\.[0-9]+Z$"; "Z") | sub("T"; " ") | sub("Z$"; ""))
            end;
        (.result.rules // []) | to_entries[] |
        "#\(.key + 1)  \(.value.action // "?")\n" +
        "    \(.value.description // "(no description)")\n" +
        "    id:                \(.value.id // "")\n" +
        "    enabled:           \(if .value.enabled == false then "no" else "yes" end)\n" +
        "    logging:           \(if .value.logging.enabled == true then "enabled" else "disabled" end)\n" +
        "    last_updated:      \(.value.last_updated | human_date)\n" +
        (if .value.action_parameters then "    action_parameters: \(.value.action_parameters | tojson)\n" else "" end) +
        "    expression:        \(.value.expression // "")\n" +
        "\n"
    '
}

# =====================================
# -- _cf_ruleset_render_csv $DOMAIN_NAME $ZONE_ID
# -- One header per process, then one RFC 4180-quoted row per rule.
# =====================================
function _cf_ruleset_render_csv () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2

    if [[ ${CF_CSV_HEADER_PRINTED:-0} -ne 1 ]]; then
        printf 'domain,zone_id,position,rule_id,action,enabled,logging,description,expression\n'
        CF_CSV_HEADER_PRINTED=1
    fi

    printf '%s' "$RULESET_API_OUTPUT" | jq -r \
        --arg domain "$DOMAIN_NAME" \
        --arg zone_id "$ZONE_ID" \
        '(.result.rules // []) | to_entries[] | [
            $domain,
            $zone_id,
            (.key + 1),
            (.value.id // ""),
            (.value.action // ""),
            (if .value.enabled == false then "no" else "yes" end),
            (if .value.logging.enabled == true then "enabled" else "disabled" end),
            (.value.description // ""),
            (.value.expression // "")
        ] | @csv'
}

function cf_ruleset_list_rules () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2

    _debug "function:${FUNCNAME[0]} - Listing rules from entry point on zone $ZONE_ID"

    # cf_ruleset_get_entrypoint echoes the body; keep stdout for the renderer.
    cf_ruleset_get_entrypoint "$ZONE_ID" >/dev/null
    local GET_EXIT=$?
    if [[ $GET_EXIT -eq 2 ]]; then
        _error "Failed to retrieve rules for zone $ZONE_ID"
        return 1
    fi

    _cf_ruleset_render_list "$DOMAIN_NAME" "$ZONE_ID"
}

function _cf_ruleset_get_or_create_entrypoint () {
    local ZONE_ID=$1
    local RULES_JSON=${2:-"[]"}
    
    _debug "function:${FUNCNAME[0]} - Getting or creating entry point on zone $ZONE_ID"
    
    # shellcheck disable=SC2034
    GET_OR_CREATE_RULESET_ID=""
    GET_OR_CREATE_RULESET_JSON=""
    GET_OR_CREATE_WAS_CREATED=0
    
    # Try to get existing entry point.
    # Redirect stdout to /dev/null: cf_ruleset_get_entrypoint echoes the full
    # API response JSON, but we only need the exit code + RULESET_API_OUTPUT global.
    cf_ruleset_get_entrypoint "$ZONE_ID" > /dev/null
    local GET_EXIT=$?
    if [[ $GET_EXIT -eq 0 ]]; then
        # Entry point exists — snapshot the body before anything else writes it
        GET_OR_CREATE_RULESET_JSON=$RULESET_API_OUTPUT
        GET_OR_CREATE_RULESET_ID=$(printf '%s' "$RULESET_API_OUTPUT" | jq -r '.result.id // empty')
        _debug "Existing entry point ruleset found: $GET_OR_CREATE_RULESET_ID"
        return 0
    fi
    
    if [[ $GET_EXIT -eq 1 ]]; then
        # 404 - not found, create a new one
        _debug "Entry point not found, creating new one"
        local CREATE_EXIT
        if cf_ruleset_create_entrypoint "$ZONE_ID" "$RULES_JSON"; then
            CREATE_EXIT=0
        else
            CREATE_EXIT=1
        fi
        
        if [[ $CREATE_EXIT -eq 0 ]]; then
            # shellcheck disable=SC2034
            GET_OR_CREATE_WAS_CREATED=1
            GET_OR_CREATE_RULESET_ID=$CF_CREATED_RULESET_ID
            GET_OR_CREATE_RULESET_JSON=$CF_CREATED_RULESET_JSON
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

function cf_ruleset_apply_profile () {
    local ZONE_ID=$1
    local RULES_JSON=$2
    
    _debug "function:${FUNCNAME[0]} - Applying profile to zone $ZONE_ID"
    
    # Call the helper directly: a command substitution would run it in a
    # subshell and discard the globals it reports back to us.
    if ! _cf_ruleset_get_or_create_entrypoint "$ZONE_ID" "$RULES_JSON"; then
        _error "Could not obtain entry point ruleset for zone $ZONE_ID"
        return 1
    fi
    
    local RULESET_ID=$GET_OR_CREATE_RULESET_ID
    if [[ -z "$RULESET_ID" ]]; then
        _error "Could not obtain entry point ruleset ID for zone $ZONE_ID"
        return 1
    fi
    
    # shellcheck disable=SC2034
    CF_APPLIED_RULESET_ID=$RULESET_ID
    
    # If it was newly created with rules already, we're done
    if [[ ${GET_OR_CREATE_WAS_CREATED:-0} -eq 1 ]] && [[ "$RULES_JSON" != "[]" ]]; then
        _cf_ruleset_render_table "" "$ZONE_ID" "$GET_OR_CREATE_RULESET_JSON" >&2
        return 0
    fi
    
    # Existing ruleset found — confirm replacement unless SKIP_CONFIRM is set
    if [[ "${SKIP_CONFIRM:-0}" -ne 1 ]]; then
        local existing_count new_count
        existing_count=$(printf '%s' "$GET_OR_CREATE_RULESET_JSON" | jq -r '(.result.rules // []) | length' 2>/dev/null)
        existing_count=${existing_count:-0}
        new_count=$(printf '%s' "$RULES_JSON" | jq -r 'length' 2>/dev/null)
        new_count=${new_count:-0}

        _warning "This zone already has ${existing_count} rule(s) in the entry point ruleset."
        if [[ "$existing_count" -gt 0 ]]; then
            _cf_ruleset_render_table "" "$ZONE_ID" "$GET_OR_CREATE_RULESET_JSON" >&2
        fi
        _warning "The profile contains ${new_count} rule(s)."

        if ! ui_confirm "Replace all existing rules?" n; then
            _warning "Operation cancelled by user"
            return 1
        fi
    fi
    
    # Replace all rules
    if ! cf_ruleset_replace_all_rules "$ZONE_ID" "$RULESET_ID" "$RULES_JSON"; then
        _error "Failed to apply rules to zone $ZONE_ID"
        return 1
    fi
    
    # Show what is live now (the PUT response is still in RULESET_API_OUTPUT)
    _cf_ruleset_render_table "" "$ZONE_ID" >&2
    
    return 0
}

function cf_ruleset_list_rules_action () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2

    _debug "function:${FUNCNAME[0]} - Listing rules for $DOMAIN_NAME / $ZONE_ID"

    cf_ruleset_list_rules "$DOMAIN_NAME" "$ZONE_ID"
}

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
    
    # Ask for confirmation unless -y was given
    if [[ "${SKIP_CONFIRM:-0}" -ne 1 ]]; then
        if ! ui_confirm "Delete rule ${RULE_ID} from ${DOMAIN_NAME}/${ZONE_ID}?" n; then
            _error "Operation cancelled"
            return 1
        fi
    fi
    
    cf_ruleset_delete_rule "$ZONE_ID" "$RULESET_ID" "$RULE_ID"
}

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


# ==================================
# -- Output layer
# ==================================
# The v1 message helpers, kept as names so the engine reads the same, but now
# backed by bash-ui. Every one of them writes to stderr, so stdout stays
# data-only.
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

declare -a DOMAINS=()
declare -a LIST_FORMAT_FLAGS=()
ZONES_FILE=""
SKIP_CONFIRM=0
MULTI_ZONE=0
CONFIG_FILE=""
CF_PROFILE=""
CHALLENGE_TTL_ARG=""
TABLE_ONLY_EXPLICIT=0
CMD=""
DOMAIN=""
ZONE_ID=""

# -- Parse options
POSITIONAL=()
while (( $# )); do
	case $1 in
		-d | --domain)
			# Repeatable; a full URL is normalised to its bare domain.
			NORM_DOMAIN=$(_normalize_domain "${2:-}")
			if [[ -z $NORM_DOMAIN ]]; then
				_warning "Could not normalize domain: '${2:-}', using as-is"
				NORM_DOMAIN=${2:-}
			fi
			DOMAINS+=("$NORM_DOMAIN")
			shift 2
			;;
		-zf | --zones-file) ZONES_FILE=${2:-}; shift 2 ;;
		--config) CONFIG_FILE=${2:-}; shift 2 ;;
		--cf-profile | --cf-auth-profile) CF_PROFILE=${2:-}; shift 2 ;;
		--challenge-ttl) CHALLENGE_TTL_ARG=${2:-}; shift 2 ;;
		-y | --yes) SKIP_CONFIRM=1; shift ;;
		-c | --command) CMD=${2:-}; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		--debug)
			DEBUG=1
			# shellcheck disable=SC2034  # read by ui_debug inside vendor/bash-ui/ui.sh
			UI_VERBOSE=1
			shift
			;;
		--debug-json)
			# shellcheck disable=SC2034
			DEBUG=1
			# shellcheck disable=SC2034  # read by ui_debug inside vendor/bash-ui/ui.sh
			UI_VERBOSE=1
			# shellcheck disable=SC2034
			DEBUG_JSON=1
			shift
			;;
		--table-only)
			# Deprecated: the compact table is the default list-rules output.
			TABLE_ONLY_EXPLICIT=1
			shift
			;;
		--json | --csv | --raw) LIST_FORMAT_FLAGS+=("${1#--}"); shift ;;
		--long) LIST_LONG=1; shift ;;
		-dr | --dryrun) DRYRUN=1; shift ;;
		*) POSITIONAL+=("$1"); shift ;;
	esac
done
set -- "${POSITIONAL[@]}"

# -- Resolve the list-rules output format (exactly one at a time)
if (( ${#LIST_FORMAT_FLAGS[@]} > 1 )); then
	_error "Choose only one of --json, --csv or --raw"
	exit 2
fi
if (( ${#LIST_FORMAT_FLAGS[@]} == 1 )); then
	LIST_FORMAT=${LIST_FORMAT_FLAGS[0]}
	if [[ $TABLE_ONLY_EXPLICIT -eq 1 ]]; then
		_error "--table-only cannot be combined with --${LIST_FORMAT}"
		exit 2
	fi
fi
if [[ $LIST_LONG -eq 1 && $LIST_FORMAT != "table" ]]; then
	_error "--long only applies to the table output; drop --${LIST_FORMAT}"
	exit 2
fi

# -- Commands
# One list drives the positional form, the whitelist and the help text.
CORE_COMMANDS="create-rules update-rules upgrade-default-rules list-rules delete-rule delete-rules list-profiles print-profile validate-profile"
COMMANDS_REQUIRING_DOMAIN="create-rules update-rules upgrade-default-rules list-rules delete-rules delete-rule"
COMMANDS_SUPPORTING_MULTIZONE="create-rules update-rules list-rules delete-rules"

# Positional form: `cwr.sh create-rules default -d example.com`
if [[ -z $CMD && -n ${1:-} && " $CORE_COMMANDS " == *" $1 "* ]]; then
	CMD=$1
	shift
fi

# -- Dry run is advertised but not implemented; say so instead of pretending
if [[ ${DRYRUN:-0} == "1" ]]; then
	_error "Dry run is not implemented in cwr.sh yet"
	exit 2
fi

# -- Require a known command
if [[ -z $CMD ]]; then
	usage
	_error "No command provided"
	exit 1
fi
if [[ " $CORE_COMMANDS " != *" ${CMD} "* ]]; then
	usage
	_error "Unknown command: $CMD"
	exit 1
fi

# -- Dependencies: jq and curl carry every command that talks to Cloudflare
for app in jq curl; do
	if ! command -v "$app" >/dev/null 2>&1; then
		_error "$app is required but was not found on PATH"
		exit 1
	fi
done

# -- Load zones from a file, if one was given
if [[ -n $ZONES_FILE ]]; then
	_load_zones_file "$ZONES_FILE"
fi

# -- Per-command arguments
case $CMD in
	create-rules | update-rules | print-profile | validate-profile)
		if [[ -z ${1:-} ]]; then
			_error "No profile provided"
			cf_list_profiles
			exit 1
		fi
		;;
	delete-rule)
		if [[ -z ${1:-} ]]; then
			_error "No rule ID provided"
			exit 1
		fi
		;;
esac

# -- Domains: required, deduplicated, and single-zone unless supported
if [[ " $COMMANDS_REQUIRING_DOMAIN " == *" ${CMD} "* ]]; then
	if (( ${#DOMAINS[@]} == 0 )); then
		usage
		_error "Command '$CMD' requires at least one domain to be specified with -d or -zf"
		exit 1
	fi

	_deduplicate_zones

	if (( ${#DOMAINS[@]} > 1 )); then
		if [[ " $COMMANDS_SUPPORTING_MULTIZONE " != *" ${CMD} "* ]]; then
			_error "Command '$CMD' does not support multiple zones. Please specify a single domain with -d"
			exit 1
		fi
		MULTI_ZONE=1

		# list-rules is read-only and data-only: no confirmation prose.
		if [[ $LIST_DATA_MODE -ne 1 ]] && ! _confirm_zones; then
			exit 1
		fi
	fi

	if (( ${#DOMAINS[@]} == 1 )); then
		DOMAIN=${DOMAINS[0]}
	fi
fi

# -- Commands that need no credentials
case $CMD in
	list-profiles)
		cf_list_profiles
		exit 0
		;;
	print-profile)
		cf_print_profile "$1"
		exit $?
		;;
	validate-profile)
		cf_validate_profile "$1"
		exit $?
		;;
esac

# -- Authentication
if [[ -z $CONFIG_FILE ]]; then
	CONFIG_FILE="$HOME/.cloudflare"
fi
if ! cf_auth_init "${CF_PROFILE:-}" "$CONFIG_FILE"; then
	_error "Authentication failed"
	exit 1
fi

# -- Resolve the zone ID once for single-zone runs
if [[ " $COMMANDS_REQUIRING_DOMAIN " == *" ${CMD} "* && $MULTI_ZONE -eq 0 ]]; then
	ZONE_ID=$(_cf_zone_id "$DOMAIN")
	if [[ -z $ZONE_ID ]]; then
		_error "No zone ID found for $DOMAIN"
		exit 1
	fi
	if [[ $LIST_DATA_MODE -ne 1 ]]; then
		_running2 "Zone ID found: $ZONE_ID"
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
# -- Optionally set the Challenge Passage TTL, then create the rules.
# -- Returns non-zero if either step fails.
# =====================================
function _cf_create_rules_with_ttl () {
	local DOMAIN_NAME=$1
	local ZONE_ID=$2
	local PROFILE_NAME=$3
	local CHALLENGE_TTL=${4:-}

	# Set the TTL only when the current value is lower (skips otherwise)
	if [[ -n $CHALLENGE_TTL ]]; then
		_cf_set_challenge_ttl_if_lower "$ZONE_ID" "$CHALLENGE_TTL" || return 1
	fi

	cf_profile_create "$DOMAIN_NAME" "$ZONE_ID" "$PROFILE_NAME"
}

# -- Dispatch
case $CMD in
	create-rules)
		PROFILE=$1
		if [[ -z $PROFILE ]]; then
			_error "No profile provided"
			cf_list_profiles
			exit 1
		fi

		# --challenge-ttl applies the value directly; without it, ask once
		if [[ -n $CHALLENGE_TTL_ARG ]]; then
			TTL=$CHALLENGE_TTL_ARG
		else
			if [[ $MULTI_ZONE -eq 1 ]]; then
				TTL=$(_cf_prompt_challenge_passage "$(_cf_zone_id "${DOMAINS[0]}")")
			else
				TTL=$(_cf_prompt_challenge_passage "$ZONE_ID")
			fi
		fi

		if [[ $MULTI_ZONE -eq 1 ]]; then
			if [[ -n $TTL ]]; then
				_run_on_zones _cf_create_rules_with_ttl "\$DOMAIN" "\$ZONE_ID" "$PROFILE" "$TTL"
			else
				_run_on_zones cf_profile_create "\$DOMAIN" "\$ZONE_ID" "$PROFILE"
			fi
		else
			if [[ -n $TTL ]]; then
				_cf_create_rules_with_ttl "$DOMAIN" "$ZONE_ID" "$PROFILE" "$TTL"
			else
				cf_profile_create "$DOMAIN" "$ZONE_ID" "$PROFILE"
			fi
		fi
		;;
	update-rules)
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
		;;
	upgrade-default-rules)
		cf_upgrade_rules_default "$DOMAIN" "$ZONE_ID" "default"
		;;
	list-rules)
		if [[ $MULTI_ZONE -eq 1 ]]; then
			_run_on_zones cf_ruleset_list_rules_action "\$DOMAIN" "\$ZONE_ID"
		else
			cf_ruleset_list_rules_action "$DOMAIN" "$ZONE_ID"
		fi
		;;
	delete-rules)
		if [[ $MULTI_ZONE -eq 1 ]]; then
			_run_on_zones cf_ruleset_delete_rules_action "\$DOMAIN" "\$ZONE_ID"
		else
			cf_ruleset_delete_rules_action "$DOMAIN" "$ZONE_ID"
		fi
		;;
	delete-rule)
		cf_ruleset_delete_rule_action "$DOMAIN" "$ZONE_ID" "$1"
		;;
	*)
		usage
		_error "No command provided"
		exit 1
		;;
esac
