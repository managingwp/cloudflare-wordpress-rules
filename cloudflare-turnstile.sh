#!/bin/bash
# ---------------
# A script to manage Cloudflare turnstile
# ---------------

# ==================================
# -- Variables
# ==================================
# Get Version from VERSION located in root directory
SCRIPT_NAME=cloudflare-turnstile
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
VERSION=$(cat "${SCRIPT_DIR}/VERSION")
API_URL="https://api.cloudflare.com"
DEBUG="0"
DRYRUN="0"
REQUIRED_APPS=("jq" "column")

# ==================================================
# -- Libraries
# ==================================================
source "${SCRIPT_DIR}/lib/cloudflare-lib.sh"
source "${SCRIPT_DIR}/lib/core.sh"


# TODO a method to be able to specify different credentials loaded from shell variable or .cloudflare file.

# ==================================
# -- Usage
# ==================================
_usage () {
    echo \
"Usage: ./${SCRIPT_NAME}.sh [create <zone> <token-name> | list]

Creates appropriate api token and permissions for the Super Page Cache for Cloudflare WordPress plugin.

Commands:
    -ct|--create-turnstile <domain-name>
    -lt|--list-turnstiles <domain-name>
    -gt|--get-turnstile <account-id> <site-key>
    -ga|--get-account <domain-name>
    -dt|--delete-turnstile <account-id> <site-key>

Options:
    -d|--debug                        - Debug mode
    -dr|--dryrun                      - Dry run mode

Environment variables:
    CF_SPC_ACCOUNT      - Cloudflare account email address
    CF_SPC_KEY          - Cloudflare Global API Key
    CF_SPC_TOKEN        - Cloudflare API token.

Configuration file for credentials:
    Create a file in \$HOME/.cloudflare with both CF_SPC_ACCOUNT and CF_SPC_KEY defined or CF_SPC_TOKEN. Only use a KEY or Token, not both.

    CF_SPC_ACCOUNT=example@example.com
    CF_SPC_KEY=<global api key>    

Version: $VERSION - DIR: $SCRIPT_DIR
"
}

# =================================================================================================
# -- Functions
# =================================================================================================

# ===============================================
# -- _list_cf_turnstile_widgets $DOMAIN_NAME
# ===============================================
function _list_cf_turnstile_widgets () {
    local OUTPUT DOMAIN_NAME="$1" CF_LIST_CHALLENGE_WIDGETS
    DFUNC="${funcstack[0]}"
    _debug "Running: $DFUNC Listing Cloudflare Turnstiles on $DOMAIN_NAME"

    # -- Get account ID
    _get_domain_account_id ${DOMAIN_NAME}
    echo "Account ID: $ACCOUNT_ID"

    CF_LIST_CHALLENGE_WIDGETS="$(_cf_api "GET" "/client/v4/accounts/${ACCOUNT_ID}/challenges/widgets")"
    # Print out in a column format, id, name, mode, domains
    OUTPUT="\tName\tSitekey\tMode\tClearanceLevel\tBotFightMode(ENTONLY)\tDomains\tCreated\n"
    OUTPUT+="\t----\t-------\t----\t--------------\t-------\t-------\t-------\n"
    OUTPUT+=$(echo "$CF_LIST_CHALLENGE_WIDGETS" | jq -r '.result[] | [.name, .sitekey, .mode, .clearance_level, .bot_fight_mode, .domains[], .created_on] | @tsv')
    echo -e "$OUTPUT" | column -t
}


# ===============================================
# -- _create_cf_turnstile_widget $DOMAIN_NAME
# ===============================================
function _create_turnstile_widget () {
    local OUTPUT DOMAIN_NAME="$1"
    DFUNC="${FUNCNAME[0]}"
    _debug "Running: $DFUNC Creating Cloudflare Turnstile on $DOMAIN_NAME"

    # -- Get account ID
    _get_domain_account_id ${DOMAIN_NAME}
    echo "Account ID: $ACCOUNT_ID"

    # -- Create a new Turnstile
    # name=$DOMAIN
    # mode=managed
    # clearance_level=no_clearance
    # domains=$DOMAIN
    CF_CREATE_CHALLENGE_WIDGETS=$(_cf_api "POST-JSON" "/client/v4/accounts/${ACCOUNT_ID}/challenges/widgets" \
        '{"name":"'$DOMAIN_NAME'","mode":"managed","clearance_level":"no_clearance","domains":["'$DOMAIN_NAME'"]}')
    _running "Creating Turnstile for $DOMAIN_NAME"
    # Print out in a column format, id, name, mode, domains
    _running2 "Turnstile Sitekey and Secret: "
    echo "======================="
    echo "Sitekey: $(echo "$CF_CREATE_CHALLENGE_WIDGETS" | jq -r '.result.sitekey')"
    echo "Secret: $(echo "$CF_CREATE_CHALLENGE_WIDGETS" | jq -r '.result.secret')"
    echo "======================="
    OUTPUT="\tName\tSitekey\tMode\tClearanceLevel\tBotFightMode(ENTONLY)\tDomains\tCreated\n"
    OUTPUT+="\t----\t-------\t----\t--------------\t-------\t-------\t-------\n"
    OUTPUT+=$(echo "$CF_CREATE_CHALLENGE_WIDGETS" | jq -r '.result | [.name, .sitekey, .mode, .clearance_level, .bot_fight_mode, .domains[], .created_on] | @tsv')
    echo -e "$OUTPUT" | column -t

}

# ===============================================
# -- _get_turnstile_widget $ACCOUNT_ID $SITE_KEY
# ===============================================
function _get_turnstile_widget () {
    local OUTPUT ACCOUNT_ID="$1" SITE_KEY="$2"
    DFUNC="${FUNCNAME[0]}"
    _debug "Running: $DFUNC Getting Cloudflare Turnstile on $DOMAIN_NAME"
    _running "Getting Turnstile for $SITE_KEY with Account ID: $ACCOUNT_ID"
    # -- Get account ID    
    echo "Account ID: $ACCOUNT_ID"
    echo "Site Key: $SITE_KEY"
    echo
    CF_GET_CHALLENGE_WIDGETS=$(_cf_api "GET" "/client/v4/accounts/${ACCOUNT_ID}/challenges/widgets/${SITE_KEY}")
    if [[ $? -ne 0 ]]; then
        _error "Error getting Turnstile for $SITE_KEY"
        _error "$CF_GET_CHALLENGE_WIDGETS"
        exit 1
    fi

    echo "Challenge Widget:"
    echo "======================="
    echo "Name: $(echo "$CF_GET_CHALLENGE_WIDGETS" | jq -r '.result.name')"
    echo "Sitekey: $(echo "$CF_GET_CHALLENGE_WIDGETS" | jq -r '.result.sitekey')"
    echo "Secret: $(echo "$CF_GET_CHALLENGE_WIDGETS" | jq -r '.result.secret')"
    echo "Mode: $(echo "$CF_GET_CHALLENGE_WIDGETS" | jq -r '.result.mode')"
    echo "Clearance Level: $(echo "$CF_GET_CHALLENGE_WIDGETS" | jq -r '.result.clearance_level')"
    echo "Bot Fight Mode: $(echo "$CF_GET_CHALLENGE_WIDGETS" | jq -r '.result.bot_fight_mode')"
    echo "Domains: $(echo "$CF_GET_CHALLENGE_WIDGETS" | jq -r '.result.domains[]')"
    echo "Created: $(echo "$CF_GET_CHALLENGE_WIDGETS" | jq -r '.result.created_on')"
    echo "======================="
}

# ===============================================
# -- _delete_cf_turnstile_widget $SITE_KEY
# ===============================================
function _delete_cf_turnstile_widget () {
    local OUTPUT ACCOUNT_ID="$1" SITE_KEY="$2"
    DFUNC="${FUNCNAME[0]}"
    _debug "Running: $DFUNC Deleting Cloudflare Turnstile on $DOMAIN_NAME"
    _running "Deleting Turnstile for $SITE_KEY with Account ID: $ACCOUNT_ID"
    # -- Get account ID    
    echo "Account ID: $ACCOUNT_ID"
    echo "Site Key: $SITE_KEY"
    echo
    _get_turnstile_widget "${ACCOUNT_ID}" "${SITE_KEY}"
    # -- Confirm deletion
    read -p "Are you sure you want to delete the Turnstile with Site Key: $SITE_KEY? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # -- Delete the Turnstile
        CF_DELETE_CHALLENGE_WIDGETS=$(_cf_api "DELETE" "/client/v4/accounts/${ACCOUNT_ID}/challenges/widgets/${SITE_KEY}")
        _running "Deleting Turnstile for $SITE_KEY"
        SUCCESS_MSG=$(echo "$CF_DELETE_CHALLENGE_WIDGETS" | jq -r '.success')
        if [[ $SUCCESS_MSG == "true" ]]; then
            _success "Sucessfully deleted ${SITE_KEY}"
        else
            _warning "Deletion cancelled"
        fi
    fi

}
# =================================================================================================
# -- Main
# =================================================================================================

# -- check if parameters are set
_debug "PARAMS: ${*}"
if [[ -z ${*} ]];then
	_usage
	exit 1
fi

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -ct|--create-turnstile)
        MODE="create-token"
        DOMAIN="$2"
        shift # past argument
        shift # past value
        ;;
        -lt|--list-turnstiles)
        MODE="list"
        DOMAIN="$2"
        shift # past argument
        ;;
        -gt|--get-turnstile)
        MODE="get"
        ACCOUNT_ID="$2"
        SITE_KEY="$3"        
        shift # past argument
        shift # past value
        ;;
        -ga|--get-account)
        MODE="get-account"
        DOMAIN="$2"
        shift # past argument
        shift # past value
        ;;
        -dt|--delete-turnstile)
        MODE="delete"
        ACCOUNT_ID="$2"
        SITE_KEY="$3"      
        shift # past argument
        shift # past value
        ;;
        -d|--debug)
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

# ==================================
# -- Main Loop
# ==================================

# Set zone ID for domain.com
_debug "Running: \$CMD: $CMD"
DOMAIN_NAME=${1}

# -- Debug Enabled
if [[ $DEBUG == "1" ]]; then
    _debug "Debug enabled"
fi

# -- pre-flight check
_debug "Pre-flight_check"
pre_flight_check

# -- Run
if [[ $MODE == "create-token" ]]; then
    if [[ $DOMAIN ]]; then
        _create_turnstile_widget "${DOMAIN}"
    else
        _usage
        _error "No domain provided - ${*}"
    fi
elif [[ $MODE == "list" ]]; then
    if [[ $DOMAIN ]]; then
        _list_cf_turnstile_widgets "${DOMAIN}"        
    else
        _usage
        _error "No domain provided - ${*}"
    fi
elif [[ $MODE == "get" ]]; then
    if [[ $SITE_KEY && $ACCOUNT_ID ]]; then
        _get_turnstile_widget "${ACCOUNT_ID}" "${SITE_KEY}"
    else
        _usage
        _error "No site key or account id provided - ${*}"
    fi
elif [[ $MODE == "get-account" ]]; then
    if [[ $DOMAIN ]]; then
        _running "Getting Account ID for ${DOMAIN}"
        _get_domain_account_id "${DOMAIN}"
        echo "Account ID: $ACCOUNT_ID"
    else
        _usage
        _error "No domain provided - ${*}"
    fi
elif [[ $MODE == "delete" ]]; then
    [[ -z $SITE_KEY ]] && { _usage;_error "Please specify a site key"; exit 1;} # No domain, exit
    [[ -z $ACCOUNT_ID ]] && { _usage;_error "Please specify an account id"; exit 1;} # No domain, exit        
    _delete_cf_turnstile_widget "${ACCOUNT_ID}" "${SITE_KEY}" 
else
    _usage
    _error "No command provided - $1"
    exit 1
fi