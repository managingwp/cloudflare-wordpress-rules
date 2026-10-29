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

# ==================================
# -- Include cf-inc files
# ==================================
source "$REPO_DIR/inc/cf-inc.sh"
source "$REPO_DIR/inc/cf-inc-api.sh"
source "$REPO_DIR/inc/cf-inc-wp.sh"
source "$REPO_DIR/inc/cf-inc-auth.sh"
source "$REPO_DIR/inc/cf-inc-rulesets.sh"
# cf-inc-old.sh was archived in Phase 7 — it contained only the unused CF_PROTECT_WP function

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
if [[ " ${COMMANDS_REQUIRING_DOMAIN[*]} " =~ " ${CMD} " && $MULTI_ZONE -eq 0 ]]; then
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
