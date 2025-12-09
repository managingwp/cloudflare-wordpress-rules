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
export PROFILE_DIR="${SCRIPT_DIR}/profiles"

# ==================================
# -- Include cf-inc files
# ==================================
source "$SCRIPT_DIR/cf-inc.sh"
source "$SCRIPT_DIR/cf-inc-api.sh"
source "$SCRIPT_DIR/cf-inc-old.sh"
source "$SCRIPT_DIR/cf-inc-wp.sh"
source "$SCRIPT_DIR/cf-inc-auth.sh"

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
	
	echo -e "${CBOLD}${CYELLOW}FILTER COMMANDS${NC}"
	echo -e "  ${CGREEN}list-filters${NC}                    List filters on domain"
	echo -e "  ${CGREEN}get-filter${NC} <id>                 Get specific filter by ID"
	echo -e "  ${CGREEN}delete-filter${NC} <id>              Delete specific filter by ID"
	echo -e "  ${CGREEN}delete-filters${NC}                  Delete all filters on domain"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}RULESET COMMANDS${NC}"
	echo -e "  ${CGREEN}list-rulesets${NC}                   List rulesets on domain"
	echo -e "  ${CGREEN}get-ruleset${NC} <id>                Get specific ruleset by ID"
	echo -e "  ${CGREEN}get-ruleset-fw-custom${NC}           Get http_request_firewall_custom ruleset"
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
	echo -e "  ${CCYAN}-d${NC}, ${CCYAN}--domain${NC} <domain>         Domain to operate on (can be used multiple times)"
	echo -e "  ${CCYAN}-zf${NC}, ${CCYAN}--zones-file${NC} <file>      Load zones from file (one per line)"
	echo -e "  ${CCYAN}-y${NC}, ${CCYAN}--yes${NC}                     Skip confirmation prompt for multi-zone ops"
	echo -e "  ${CCYAN}-c${NC}, ${CCYAN}--command${NC} <cmd>           Command to execute"
	echo -e "  ${CCYAN}--debug${NC}                         Enable debug mode"
	echo -e "  ${CCYAN}-dr${NC}, ${CCYAN}--dryrun${NC}                 Dry run, don't send to Cloudflare"
	echo ""
	
	echo -e "${CBOLD}${CYELLOW}EXAMPLES${NC}"
	echo -e "  ${CDARKGRAY}# Single domain${NC}"
	echo -e "  $SCRIPT_NAME ${CCYAN}-d${NC} domain.com ${CCYAN}-c${NC} create-rules default"
	echo ""
	echo -e "  ${CDARKGRAY}# Multiple domains${NC}"
	echo -e "  $SCRIPT_NAME ${CCYAN}-d${NC} site1.com ${CCYAN}-d${NC} site2.com ${CCYAN}-c${NC} create-rules default"
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

# -- Parse options
    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
		-d|--domain)
		# Accumulate multiple -d arguments
		DOMAINS+=("$2")
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

if ! cf_auth_init "" "$CONFIG_FILE"; then
    _error "Authentication failed"
    exit 1
fi

# -- Check if domain is required for this command
COMMANDS_REQUIRING_DOMAIN=("create-rules" "update-rules" "upgrade-default-rules" "list-rules" "delete-rules" "delete-rule" "list-filters" "get-filter" "delete-filter" "delete-filters" "list-rulesets" "get-ruleset" "get-ruleset-fw-custom" "set-settings" "get-settings")

# -- Commands that support multi-zone operations
COMMANDS_SUPPORTING_MULTIZONE=("create-rules" "update-rules" "list-rules" "delete-rules" "get-settings" "set-settings")

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
    
    # For single zone, resolve zone ID now (backward compatibility)
    if [[ $MULTI_ZONE -eq 0 ]]; then
        DOMAIN="${DOMAINS[0]}"
        ZONE_ID=$(_cf_zone_id "$DOMAIN")
        if [[ -z $ZONE_ID ]]; then
            _error "No zone ID found for $DOMAIN"
            exit 1
        else
            _running2 "Zone ID found: $ZONE_ID"
        fi
    fi
fi

if [[ $MULTI_ZONE -eq 1 ]]; then
    _running "Running $CMD on ${#DOMAINS[@]} zones"
else
    _running "Running $CMD on $DOMAIN with ID $ZONE_ID"
fi
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
    if [[ $MULTI_ZONE -eq 1 ]]; then
        _run_on_zones cf_profile_create "\$DOMAIN" "\$ZONE_ID" "$PROFILE"
    else
        cf_profile_create "$DOMAIN" "$ZONE_ID" "$PROFILE"
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
# -- list-rules
# =====================================
elif [[ $CMD == "list-rules" ]]; then
    if [[ $MULTI_ZONE -eq 1 ]]; then
        _run_on_zones cf_list_rules_action "\$DOMAIN" "\$ZONE_ID"
    else
        cf_list_rules_action "$DOMAIN" "$ZONE_ID"
    fi
# =====================================
# -- delete-rules
# =====================================
elif [[ $CMD == "delete-rules" ]]; then
    if [[ $MULTI_ZONE -eq 1 ]]; then
        _run_on_zones cf_delete_rules_action "\$DOMAIN" "\$ZONE_ID"
    else
        cf_delete_rules_action "$DOMAIN" "$ZONE_ID"
    fi
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
