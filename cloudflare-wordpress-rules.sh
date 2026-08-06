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
TABLE_ONLY="0"
export PROFILE_DIR="${SCRIPT_DIR}/profiles"

# ==================================
# -- Include cf-inc files
# ==================================
source "$SCRIPT_DIR/inc/cf-inc.sh"
source "$SCRIPT_DIR/inc/cf-inc-api.sh"
source "$SCRIPT_DIR/inc/cf-inc-wp.sh"
source "$SCRIPT_DIR/inc/cf-inc-auth.sh"
source "$SCRIPT_DIR/inc/cf-inc-rulesets.sh"
# cf-inc-old.sh was archived in Phase 7 — it contained only the unused CF_PROTECT_WP function

# ==================================
# -- usage
# ==================================
usage () {
	local CBOLD=$(tput bold)
	local CUNDERLINE=$(tput smul)
	
	echo ""
	echo -e "${CBOLD}${CCYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
	echo -e "${CBOLD}${CCYAN}║${NC}  ${CBOLD}Cloudflare WordPress Rules${NC} - Manage WAF rules across zones                  ${CBOLD}${CCYAN}║${NC}"
	echo -e "${CBOLD}${CCYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
	echo ""
	echo -e "${CBOLD}${CYELLOW}USAGE${NC}"
	echo -e "  ${CGRAY}$SCRIPT_NAME${NC} ${CGREEN}-d${NC} <domain> ${CGREEN}-c${NC} <command> [options]"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}RULE COMMANDS${NC}"
	echo -e "  ${CGREEN}create-rules${NC} <profile>          Create rules on domain using profile"
	echo -e "  ${CGREEN}update-rules${NC} <profile>          Update rules on domain using profile"
	echo -e "  ${CGREEN}upgrade-default-rules${NC}           Upgrade MWP default rules on domain"
	echo -e "  ${CGREEN}list-rules${NC}                      List rules on domain"
	echo -e "  ${CGREEN}delete-rule${NC} <id>                Delete specific rule by ID"
	echo -e "  ${CGREEN}delete-rules${NC}                    Delete all rules on domain"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}PROFILE COMMANDS${NC}"
	echo -e "  ${CGREEN}list-profiles${NC}                   List available rule profiles"
	echo -e "  ${CGREEN}print-profile${NC} <profile>         Print rules from profile"
	echo -e "  ${CGREEN}validate-profile${NC} <profile>      Validate profile JSON syntax"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}FILTER COMMANDS${NC} ${CRED}(DEPRECATED since 2025-06-15)${NC}"
	echo -e "  ${CDARKGRAY}list-filters${NC}                    List filters on domain"
	echo -e "  ${CDARKGRAY}get-filter${NC} <id>                 Get specific filter by ID"
	echo -e "  ${CDARKGRAY}delete-filter${NC} <id>              Delete specific filter by ID"
	echo -e "  ${CDARKGRAY}delete-filters${NC}                  Delete all filters on domain"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}RULESET COMMANDS${NC}"
	echo -e "  ${CGREEN}list-rulesets${NC}                   List rulesets on domain"
	echo -e "  ${CGREEN}get-ruleset${NC} <id>                Get specific ruleset by ID"
	echo -e "  ${CGREEN}get-ruleset-fw-custom${NC}           Get http_request_firewall_custom ruleset"
	echo -e "  ${CGREEN}ruleset-get-entrypoint${NC}          Get the WAF custom rules entry point"
	echo -e "  ${CGREEN}ruleset-add-rule${NC} <json>         Add a single rule to the entry point"
	echo -e "  ${CGREEN}ruleset-update-rule${NC} <id> <json> Update a single rule in the entry point"
	echo -e "  ${CGREEN}ruleset-delete-rule${NC} <id>        Delete a single rule from the entry point"
	echo -e "  ${CGREEN}migrate-to-rulesets${NC} [--delete-old]  Migrate old Firewall Rules to Rulesets API"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}SETTINGS COMMANDS${NC}"
	echo -e "  ${CGREEN}get-settings${NC}                    Get security settings on domain"
	echo -e "  ${CGREEN}set-settings${NC} <setting> <value>  Set security setting"
	echo -e "    ${CDARKGRAY}Settings: security_level, challenge_ttl, browser_integrity_check, always_use_https${NC}"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}AUTH COMMANDS${NC}"
	echo -e "  ${CGREEN}list-auth-profiles${NC}              List available authentication profiles"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}OPTIONS${NC}"
	echo -e "  ${CCYAN}-d${NC}, ${CCYAN}--domain${NC} <domain>         Domain or full URL, normalized to domain (can be used multiple times)"
	echo -e "  ${CCYAN}-zf${NC}, ${CCYAN}--zones-file${NC} <file>      Load zones from file (one per line)"
	echo -e "  ${CCYAN}-y${NC}, ${CCYAN}--yes${NC}                     Skip confirmation prompt for multi-zone ops"
	echo -e "  ${CCYAN}-c${NC}, ${CCYAN}--command${NC} <cmd>           Command to execute"
    echo -e "  ${CCYAN}--cf-profile${NC} <name>            Cloudflare auth profile from .cloudflare"
    echo -e "  ${CDARKGRAY}--cf-auth-profile${NC} <name>      Alias for --cf-profile"
    echo -e "  ${CCYAN}--challenge-ttl${NC} <seconds>       Challenge Passage TTL (bypasses interactive prompt)"
	echo -e "  ${CCYAN}--debug${NC}                         Enable debug mode"
    echo -e "  ${CCYAN}--table-only${NC}                    list-rules only: show table output and errors only"
	echo -e "  ${CCYAN}-dr${NC}, ${CCYAN}--dryrun${NC}                 Dry run, don't send to Cloudflare"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}EXAMPLES${NC}"
	echo -e "  ${CDARKGRAY}# Single domain${NC}"
	echo -e "  $SCRIPT_NAME ${CCYAN}-d${NC} domain.com ${CCYAN}-c${NC} create-rules default"
    echo -e "  $SCRIPT_NAME ${CCYAN}-d${NC} domain.com ${CCYAN}-c${NC} create-rules default ${CCYAN}--cf-profile${NC} PROD"
	echo ""
	echo -e "  ${CDARKGRAY}# Multiple domains${NC}"
	echo -e "  $SCRIPT_NAME ${CCYAN}-d${NC} site1.com ${CCYAN}-d${NC} site2.com ${CCYAN}-c${NC} create-rules default"
	echo ""
	echo -e "  ${CDARKGRAY}# With Challenge TTL (bypasses interactive prompt)${NC}"
	echo -e "  $SCRIPT_NAME ${CCYAN}-d${NC} domain.com ${CCYAN}-c${NC} create-rules default ${CCYAN}--challenge-ttl${NC} 3600"
	echo ""
	echo -e "  ${CDARKGRAY}# Using zones file${NC}"
	echo -e "  $SCRIPT_NAME ${CCYAN}-zf${NC} zones.txt ${CCYAN}-c${NC} create-rules default"
	echo ""
	echo -e "  ${CDARKGRAY}# Skip confirmation for batch operations${NC}"
	echo -e "  $SCRIPT_NAME ${CCYAN}-zf${NC} zones.txt ${CCYAN}-c${NC} delete-rules ${CCYAN}-y${NC}"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}AUTHENTICATION${NC}"
	echo -e "  Place credentials in ${CUNDERLINE}\$HOME/.cloudflare${NC}"
	echo -e "  Supports multiple profiles: ${CGRAY}CF_TOKEN_PROD${NC}, ${CGRAY}CF_ACCOUNT_DEV/CF_KEY_DEV${NC}, etc."
	echo -e "  Run '${CGREEN}list-auth-profiles${NC}' to see available profiles"
	echo -e "  See ${CGRAY}.cloudflare.example${NC} for configuration format"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}MULTI-ZONE SUPPORT${NC} ${CDARKGRAY}(v2.2.0+)${NC}"
	echo -e "  Commands supporting multi-zone: ${CGREEN}create-rules${NC}, ${CGREEN}update-rules${NC}, ${CGREEN}list-rules${NC},"
	echo -e "  ${CGREEN}delete-rules${NC}, ${CGREEN}get-settings${NC}, ${CGREEN}set-settings${NC}"
	echo ""
	
	echo -e "${CDARKGRAY}Version: ${VERSION}${NC}"
	echo ""
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
        --debug)
        # shellcheck disable=SC2034
        DEBUG=1    
        shift # past argument        
        ;;
        --debug-json)
        # shellcheck disable=SC2034
        DEBUG=1
        # shellcheck disable=SC2034
        DEBUG_JSON=1
        shift # past argument
        ;;
        --table-only)
        TABLE_ONLY="1"
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
COMMANDS_NO_AUTH=("list-profiles" "print-profile" "list-auth-profiles" "validate-profile")
COMMANDS_REQUIRING_AUTH=("create-rules" "update-rules" "upgrade-default-rules" "list-rules" "delete-rule" "delete-rules" "list-filters" "get-filter" "delete-filter" "delete-filters" "list-rulesets" "get-ruleset" "get-ruleset-fw-custom" "set-settings" "get-settings" "ruleset-get-entrypoint" "ruleset-add-rule" "ruleset-update-rule" "ruleset-delete-rule" "migrate-to-rulesets")
ALL_COMMANDS=("${COMMANDS_NO_AUTH[@]}" "${COMMANDS_REQUIRING_AUTH[@]}")

if [[ ! " ${ALL_COMMANDS[*]} " =~ " ${CMD} " ]]; then
    usage
    _error "Unknown command: $CMD"
    exit 1
fi

# -- Argument validation
if [[ $CMD == "create-rules" || $CMD == "update-rules" ]]; then
    if [[ -z $1 ]]; then
        _error "No profile provided"
        cf_list_profiles
        exit 1
    fi
elif [[ $CMD == "delete-rule" ]]; then
    if [[ -z $1 ]]; then
        _error "No rule ID provided"
        exit 1
    fi
elif [[ $CMD == "get-filter" || $CMD == "delete-filter" ]]; then
    if [[ -z $1 ]]; then
        usage
        _error "No filter ID provided"
        exit 1
    fi
elif [[ $CMD == "get-ruleset" ]]; then
    if [[ -z $1 ]]; then
        usage
        _error "No ruleset ID provided"
        exit 1
    fi
elif [[ $CMD == "ruleset-update-rule" || $CMD == "ruleset-delete-rule" ]]; then
    if [[ -z $1 ]]; then
        usage
        _error "No rule ID provided"
        exit 1
    fi
elif [[ $CMD == "ruleset-add-rule" ]]; then
    if [[ -z $1 ]]; then
        usage
        _error "No rule JSON provided"
        exit 1
    fi
elif [[ $CMD == "set-settings" ]]; then
    if [[ -z $1 || -z $2 ]]; then
        usage
        _error "set-settings requires <setting> <value>"
        exit 1
    fi
fi

# -- Check if domain is required for this command
COMMANDS_REQUIRING_DOMAIN=("create-rules" "update-rules" "upgrade-default-rules" "list-rules" "delete-rules" "delete-rule" "list-filters" "get-filter" "delete-filter" "delete-filters" "list-rulesets" "get-ruleset" "get-ruleset-fw-custom" "set-settings" "get-settings" "ruleset-get-entrypoint" "ruleset-add-rule" "ruleset-update-rule" "ruleset-delete-rule" "migrate-to-rulesets")

# -- Commands that support multi-zone operations
COMMANDS_SUPPORTING_MULTIZONE=("create-rules" "update-rules" "list-rules" "delete-rules" "get-settings" "set-settings" "ruleset-get-entrypoint")

if [[ " ${COMMANDS_REQUIRING_DOMAIN[*]} " =~ " ${CMD} " ]]; then
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
        if [[ ! " ${COMMANDS_SUPPORTING_MULTIZONE[*]} " =~ " ${CMD} " ]]; then
            _error "Command '$CMD' does not support multiple zones. Please specify a single domain with -d"
            exit 1
        fi
        MULTI_ZONE=1

        # Confirm with user unless -y flag was used
        if ! _confirm_zones; then
            exit 1
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
    exit 0
elif [[ $CMD == "list-auth-profiles" ]]; then
    # Use CONFIG_FILE if set via --config, otherwise use first positional arg or default
    if [[ -z "$CONFIG_FILE" ]]; then
        CONFIG_FILE="${1:-$HOME/.cloudflare}"
    fi
    # Make sure it's an absolute path
    if [[ ! "$CONFIG_FILE" =~ ^/ ]]; then
        if [[ -f "$CONFIG_FILE" ]]; then
            CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
        elif [[ -f "$HOME/$CONFIG_FILE" ]]; then
            CONFIG_FILE="$HOME/$CONFIG_FILE"
        elif [[ -f "./$CONFIG_FILE" ]]; then
            CONFIG_FILE="$(pwd)/$CONFIG_FILE"
        fi
    fi
    cf_auth_list_profiles "$CONFIG_FILE"
    exit 0
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

LIST_TABLE_ONLY_MODE=0
if [[ $CMD == "list-rules" && $TABLE_ONLY -eq 1 ]]; then
    LIST_TABLE_ONLY_MODE=1
fi

# For single zone, resolve zone ID now (backward compatibility)
if [[ " ${COMMANDS_REQUIRING_DOMAIN[*]} " =~ " ${CMD} " && $MULTI_ZONE -eq 0 ]]; then
    DOMAIN="${DOMAINS[0]}"
    ZONE_ID=$(_cf_zone_id "$DOMAIN")
    if [[ -z $ZONE_ID ]]; then
        _error "No zone ID found for $DOMAIN"
        exit 1
    else
        if [[ $LIST_TABLE_ONLY_MODE -ne 1 ]]; then
            _running2 "Zone ID found: $ZONE_ID"
        fi
    fi
fi

if [[ $LIST_TABLE_ONLY_MODE -ne 1 ]]; then
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
        _run_on_zones cf_ruleset_list_rules_action "\$DOMAIN" "\$ZONE_ID" "$TABLE_ONLY"
    else
        cf_ruleset_list_rules_action "$DOMAIN" "$ZONE_ID" "$TABLE_ONLY"
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
# =====================================
# -- list-filters (DEPRECATED)
# =====================================
elif [[ $CMD == "list-filters" ]]; then
    _warning "Filters API is deprecated since 2025-06-15. Use 'list-rules' instead (Rulesets API)."
    cf_list_filters_action "$DOMAIN" "$ZONE_ID"
# =====================================
# -- get-filter (DEPRECATED)
# =====================================
elif [[ $CMD == "get-filter" ]]; then
    _warning "Filters API is deprecated since 2025-06-15. Use 'ruleset-get-entrypoint' instead."
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
# -- delete-filter (DEPRECATED)
# =====================================
elif [[ $CMD == "delete-filter" ]]; then
    _warning "Filters API is deprecated since 2025-06-15. Rulesets API does not use separate filters."
	FILTER_ID=$1
    [[ $FILTER_ID == "" ]] && _error "No filter ID provided" && exit 1
	cf_delete_filter_action "$DOMAIN" "$ZONE_ID" "$FILTER_ID"
# =====================================
# -- delete-filters (DEPRECATED)
# =====================================
elif [[ $CMD == "delete-filters" ]]; then
    _warning "Filters API is deprecated since 2025-06-15. Rulesets API does not use separate filters."
	cf_delete_filters_action "$DOMAIN" "$ZONE_ID"

# =====================================
# -- list-rulesets
# =====================================
elif [[ $CMD == "list-rulesets" ]]; then
	_running2 "Listing rulesets"
	cf_list_rulesets "$ZONE_ID"
# =====================================
# -- get-ruleset
# =====================================
elif [[ $CMD == "get-ruleset" ]]; then
	RULESET_ID=$1
	_running2 "Getting ruleset ID $RULESET_ID"
	if [[ -z $RULESET_ID ]]; then
		usage
		_error "No ruleset ID provided"
		exit 1
	else
		cf_get_ruleset "$ZONE_ID" "$RULESET_ID"
	fi
# =====================================
# -- get-ruleset-fw-custom
# =====================================
elif [[ $CMD == "get-ruleset-fw-custom" ]]; then	
	_running2 "Getting http_request_firewall_custom ruleset"
	cf_get_ruleset_fw_custom "$ZONE_ID"	
# =====================================
# -- ruleset-get-entrypoint
# =====================================
elif [[ $CMD == "ruleset-get-entrypoint" ]]; then
    if [[ $MULTI_ZONE -eq 1 ]]; then
        _run_on_zones cf_ruleset_get_entrypoint_action "\$DOMAIN" "\$ZONE_ID"
    else
        cf_ruleset_get_entrypoint_action "$DOMAIN" "$ZONE_ID"
    fi
# =====================================
# -- ruleset-add-rule
# =====================================
elif [[ $CMD == "ruleset-add-rule" ]]; then
    RULE_JSON=$1
    POSITION_JSON=${2:-}
    if [[ -z $RULE_JSON ]]; then
        _error "No rule JSON provided"
        exit 1
    fi
    if [[ $MULTI_ZONE -eq 1 ]]; then
        _run_on_zones cf_ruleset_add_rule_action "\$DOMAIN" "\$ZONE_ID" "$RULE_JSON" "$POSITION_JSON"
    else
        cf_ruleset_add_rule_action "$DOMAIN" "$ZONE_ID" "$RULE_JSON" "$POSITION_JSON"
    fi
# =====================================
# -- ruleset-update-rule
# =====================================
elif [[ $CMD == "ruleset-update-rule" ]]; then
    RULE_ID=$1
    RULE_JSON=$2
    if [[ -z $RULE_ID ]]; then
        _error "No rule ID provided"
        exit 1
    fi
    if [[ -z $RULE_JSON ]]; then
        _error "No rule JSON provided"
        exit 1
    fi
    cf_ruleset_update_rule_action "$DOMAIN" "$ZONE_ID" "$RULE_ID" "$RULE_JSON"
# =====================================
# -- ruleset-delete-rule
# =====================================
elif [[ $CMD == "ruleset-delete-rule" ]]; then
    RULE_ID=$1
    if [[ -z $RULE_ID ]]; then
        _error "No rule ID provided"
        exit 1
    fi
    cf_ruleset_delete_rule_action "$DOMAIN" "$ZONE_ID" "$RULE_ID"
# =====================================
# -- migrate-to-rulesets
# =====================================
elif [[ $CMD == "migrate-to-rulesets" ]]; then
    DELETE_OLD=0
    if [[ "$1" == "--delete-old" ]]; then
        DELETE_OLD=1
        shift
    fi
    if [[ $MULTI_ZONE -eq 1 ]]; then
        _run_on_zones cf_ruleset_migrate_existing "\$DOMAIN" "\$ZONE_ID" "$DELETE_OLD"
    else
        cf_ruleset_migrate_existing "$DOMAIN" "$ZONE_ID" "$DELETE_OLD"
    fi
# ================
# -- set-settings
# ================
elif [[ $CMD == "set-settings" ]]; then	# -- Run set settings
	_running "  Running Set settings"
	if [[ $MULTI_ZONE -eq 1 ]]; then
	    _run_on_zones _cf_set_settings "\$ZONE_ID" "$@"
	else
	    _cf_set_settings "$ZONE_ID" "$@"
	fi
# ================
# -- get-settings
# ================
elif [[ $CMD == "get-settings" ]]; then	
	if [[ $MULTI_ZONE -eq 1 ]]; then
	    _run_on_zones _cf_get_settings "\$ZONE_ID" "$@"
	else
	    _cf_get_settings "$ZONE_ID" "$@"
	fi
# =====================================
# -- list-auth-profiles
# =====================================
elif [[ $CMD == "list-auth-profiles" ]]; then
	cf_auth_list_profiles
else
    usage
    _error "No command provided"
    exit 1
fi
