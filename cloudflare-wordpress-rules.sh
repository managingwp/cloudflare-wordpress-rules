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
	echo "Usage: $SCRIPT_NAME -d <domain> -c <command>"
	echo 
	echo " Commands"
	echo
	echo "   create-rules <profile>                     - Create rules on domain using profile"
	echo "   update-rules <profile>                     - Update rules on domain using profile"
	echo "   upgrade-default-rules                      - Upgrade MWP default rules on domain"
	echo
	echo "   list-profiles                              - List profiles"
	echo "   print-profile <profile>                    - Print rules from profile"
	echo "   validate-profile <profile>                 - Validate profile JSON syntax and structure"
	echo ""
	echo "Authentication Commands"
	echo "   list-auth-profiles                         - List available authentication profiles"
	echo
	echo "   list-rules                                 - List rules"
	echo "   delete-rule <id>                           - Delete rule"
	echo "   delete-rules                               - Delete all rules"
	echo
	echo "   list-filters <id>                          - Get Filters"
	echo "   delete-filter <id>                         - Delete rule ID on domain"
	echo "   delete-filters                             - Delete all filters"
	echo
	echo "Ruleset Commands"
	echo "   list-rulesets                              - List rulesets"
	echo "   get-ruleset <id>                           - Get ruleset ID on domain"
	echo "   get-ruleset-fw-custom                      - Get http_request_firewall_custom ruleset"
	echo 
	echo "   get-settings <domain>                      - Get security settings on domain"
	echo "   set-settings <domain> <setting> <value>    - Set security settings on domain"
	echo "         security_level"
	echo "         challenge_ttl"
	echo "         browser_integrity_check"
	echo "         always_use_https"
	echo 
	echo " Options"
	echo "   --debug                 - Debug mode"
	echo "   -dr                     - Dry run, don't send to Cloudflare"
	echo 
	echo " Profiles - See profiles directory for example."
	echo "   default                             - Default profile"
	echo 
	echo "Examples"
	echo "   $SCRIPT_NAME -d domain.com -c delete-filter 32341983412384bv213v"
	echo "   $SCRIPT_NAME -d domain.com -c create-rules"
	echo ""
	echo "Cloudflare API Credentials:"
	echo "  Place credentials in \$HOME/.cloudflare"
	echo "  Supports multiple profiles: CF_PROD_TOKEN, CF_DEV_ACCOUNT/CF_DEV_KEY, etc."
	echo "  Use 'list-auth-profiles' to see available profiles"
	echo "  See .cloudflare.example for configuration format"
	echo ""
	echo "Version: $VERSION"
}

# =============================================================================
# -- main
# =============================================================================

# -- Parse options
    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
		-d|--domain)
		DOMAIN="$2"
		shift # past argument
		shift # past variable
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
    cf_auth_list_profiles
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
if ! cf_auth_init; then
    _error "Authentication failed"
    exit 1
fi

# -- Show usage if no domain provided
if [[ -n $DOMAIN ]]; then
    ZONE_ID=$(_cf_zone_id "$DOMAIN")	
	if [[ -z $ZONE_ID ]]; then
		_error "No zone ID found for $DOMAIN"
		exit 1
	else
		_running2 "Zone ID found: $ZONE_ID"
	fi
fi

_running "Running $CMD on $DOMAIN with ID $ZONE_ID"
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
    cf_profile_create "$DOMAIN" "$ZONE_ID" "$PROFILE"
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
    cf_update_rules "$DOMAIN" "$ZONE_ID" "$PROFILE"
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
    cf_list_rules_action "$DOMAIN" "$ZONE_ID"
# =====================================
# -- delete-rules
# =====================================
elif [[ $CMD == "delete-rules" ]]; then
    cf_delete_rules_action "$DOMAIN" "$ZONE_ID"
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
	_cf_set_settings "$ZONE_ID" "$@"
# ================
# -- get-settings
# ================
elif [[ $CMD == "get-settings" ]]; then	
	_cf_get_settings "$ZONE_ID"
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
