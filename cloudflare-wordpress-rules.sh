#!/usr/bin/env bash
# ==================================================
# -- Variables
# ==================================================
SCRIPT_NAME="cloudflare-wordpress-rules"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
VERSION=$(cat "${SCRIPT_DIR}/VERSION")
API_URL="https://api.cloudflare.com"
DEBUG="0"
DRYRUN="0"
REQUIRED_APPS=("jq" "column")
PROFILE_DIR="${SCRIPT_DIR}/profiles"


# ==================================================
# -- Libraries
# ==================================================
source "${SCRIPT_DIR}/lib/cloudflare-lib.sh"
source "${SCRIPT_DIR}/lib/cloudflare-lib-old.sh"
source "${SCRIPT_DIR}/lib/core.sh"


# -- usage
usage () {
	echo "Usage: $SCRIPT_NAME (-d|--domain) <command>"
	echo
	echo " Options"
	echo "   -d|--domain <domain>       - Domain to run command on"
	echo "   --debug					- Debug mode" 
	echo 
	echo " Commands"
	echo "   list-rulset-profiles                  -List available profiles"
	echo "   create-ruleset-profile <profile>      - Create rulset based on profile for domain"
	echo "                                              default  - Based on https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/cloudflare-protect-wordpress.md"
	echo 
	echo "   create-ruleset <ruleset>              - Create ruleset based on profile for domain"
	echo "   get-rulesets                          - Get rulesets"
	echo "   delete-ruleset <id>                   - Delete rule"
	echo "   delete-all-rulesets                   - Delete all rules"
	echo 
	echo "   set-settings <setting> <value>        - Set security settings on domain"
	echo "         security_level"
	echo "         challenge_ttl"
	echo "         browser_integrity_check"
	echo "         always_use_https"
	echo 
	echo "   get-settings                          - Get security settings on domain"
	echo 
	echo
	echo "Examples"
	echo "   $SCRIPT_NAME -d domain.com delete-ruleset 32341983412384bv213v"
	echo "   $SCRIPT_NAME -d create-ruleseet-profile default"
	echo ""
	echo "Cloudflare API Credentials should be placed in \$HOME/.cloudflare"
	echo ""
	echo "Version: $VERSION"
}

# -- usage_set_settings
function usage_set_settings () {
	echo "Usage: $SCRIPT_NAME -d <domain> set-settings <setting> <value>"
	echo ""
	echo " Settings"
	# -- Loop through CF_SETTINGS array and print out key
	for i in "${!CF_SETTINGS[@]}"; do
		echo "   ${i}"
	done
	echo ""
}


# ==================================================
# ==================================================
# -- Main loop
# ==================================================
# ==================================================

# -- Parse options
    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
		-d|--domain)
		DOMAIN="$2"
		shift # past argument
		shift # past value
		;;
        --debug)
        DEBUG="1"
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
CMD=$1

# -- Dryrun
if [[ $DRYRUN = "1" ]]; then
	_error "Dryrun not implemented yet"
fi

# -- Check for .cloudflare credentials
pre_flight_check

# -- Show usage if no domain provided
if [[ -z $DOMAIN ]]; then
    usage
    _error "No domain provided"
    exit 1
fi

# -- Check $CMD
if [[ -z $CMD ]]; then
	usage
	_error "No command provided"
	exit 1
fi

# -- Check if domain is valid
CF_ZONE_ID=$(_get_zone_id $DOMAIN >&1)
EXIT_CODE=$?
_debug "main: CF_ZONE_ID: $CF_ZONE_ID EXIT_CODE: $EXIT_CODE"
if [[ $EXIT_CODE == "1" ]]; then
	exit 1
fi


# ================
# -- create-ruleset
# ================
if [[ $CMD == "list-rulset-profiles" ]]; then
	_running "Running list-rulset-profiles on $DOMAIN"
	_cf_list_ruleset_profiles 
elif [[ $CMD == "create-ruleset-profile" ]]; then
	PROFILE=$3
	_running "Running create-ruleset on $DOMAIN"
	if [[ -z $PROFILE ]]; then
		_running2 "Missing profile name, using default for rules"
		[[ $? == "1" ]] && exit 1
		_cf_create_ruleset_profile $CF_ZONE_ID "default"		
	else
		_running2 "Creating rulesets on $CF_ZONE_ID using profile $PROFILE"
		_cf_create_ruleset_profile $CF_ZONE_ID $PROFILE
	fi
# ================
# -- create-ruleset
# ================
elif [[ $CMD == "create-ruleset" ]]; then
	RULESET=$3
	[[ -z $RULESET ]] && { usage;_error "No ruleset provided";exit 1; }
	_running "Running create-ruleset on $DOMAIN"
	_cf_create_ruleset $CF_ZONE_ID $RULESET
# ================
# -- get-rulesets
# ================
elif [[ $CMD == "get-rulesets" ]]; then	
    _running "Running $CMD on $DOMAIN/$CF_ZONE_ID"
    _cf_get_ruleset $CF_ZONE_ID
# ================
# -- delete-rule
# ================
elif [[ $CMD == "delete-ruleset" ]]; then
	RULESET_ID=$3
	_running "Running $CMD on $DOMAIN/$CF_ZONE_ID with ruleset ID $RULESET_ID"    
    _cf_delete_ruleset $CF_ZONE_ID $RULESET_ID
# =================
# -- delete-all-rulesets
# =================
elif [[ $CMD == "delete-all-rulesets" ]]; then
	_running "Running $CMD on $DOMAIN/$CF_ZONE_ID"
	CF_DELETE_ALL_RULES $CF_ZONE_ID
# ================
# -- set-settings
# ================
elif [[ $CMD == "set-settings" ]]; then
	CF_SETTING=$2
	CF_VALUE=$3
	[[ -z $CF_SETTING ]] && { usage_set_settings;_error "No setting provided";exit 1; }
	[[ -z $CF_VALUE ]] && { usage_set_settings;_error "No value provided";_cf_settings_values $CF_SETTING;exit 1; }

	# -- Check if valid setting using CF_SETTINGS array
	if ! _cf_check_setting $CF_SETTING; then
		_error "Invalid setting provided"
		exit 1
	fi

	if ! _cf_check_setting_value $CF_SETTING $CF_VALUE; then
		_error "Invalid value provided"
		exit 1
	fi

	# -- Run set settings
	_running "  Running Set settings"
	_cf_set_settings $CF_ZONE_ID $CF_SETTING $CF_VALUE
# ================
# -- get-settings
# ================
elif [[ $CMD == "get-settings" ]]; then	
	_running "  Running Get settings"
	_cf_get_settings $CF_ZONE_ID
else
	usage 
	_error "No command provided"
	exit 1

fi
