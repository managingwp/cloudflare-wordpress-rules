#!/bin/bash
# ---------------
# A script to create the necessary Cloudflare rules for the Super Page Cache for Cloudflare WordPress Plugin
# ---------------

# ==================================
# -- Variables
# ==================================
# Get Version from VERSION located in root directory
SCRIPT_NAME=cloudflare-turnstile
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
VERSION=$(cat "${SCRIPT_DIR}/VERSION")
DEBUG="0"
DRYRUN="0"
QUIET="0"
TURNSTILE_ID=""
ZONE=""


# ==================================
# -- Include cf-inc files
# ==================================
source "$SCRIPT_DIR/cf-inc.sh"
source "$SCRIPT_DIR/cf-inc-api.sh"
source "$SCRIPT_DIR/cf-inc-auth.sh"


# ==================================
# -- Usage
# ==================================
usage () {
    echo \
"Usage: ./${SCRIPT_NAME}.sh [create <zone> <name> | list]

Creates appropriate Cloudflare turnstile api id and key.

Commands:
    create -z <domain-name> -tn <turnstile-name> (-z|-a|-t|-ak)                  - Creates a turnstile called <turnstile name> for <zone>, if <turnstile-name> blank then (zone)-spc used
    list -t [turnstile sitekey] | -z [domain name] | -a [accountemail]           - Lists account turnstiles.
    delete -t [turnstile sitekey] | -z [domain name] | -a [accountemail]         - Deletes a turnstile.
    test-creds -t [turnstile sitekey] | -a [account] -ak [api-key]               - Test credentials against Cloudflare API.
    list-auth-profiles                                                           - List available authentication profiles

Options:
    -z|--zone [domain name]                - Zone domain name
    -a|--account [name@email.com]          - Cloudflare account email address
    -aid|--account-id [account id]         - Cloudflare account id
    -t|--turnstile [turnstile sitekey]     - Turnstile Sitekey
    -tn|--turnstile-name [name]            - Turnstile Name
    -ak|--apikey [apikey]                  - API Key to use for creating the new turnstile.
    -d|--debug                             - Debug mode
    -dr|--dryrun                           - Dry run mode

Cloudflare API Credentials:
    Place credentials in \$HOME/.cloudflare
    Supports multiple profiles: CF_TOKEN_PROD, CF_ACCOUNT_DEV/CF_KEY_DEV, etc.
    Use 'list-auth-profiles' to see available profiles
    See .cloudflare.example for configuration format
    
    Legacy environment variables (still supported):
        CF_ACCOUNT_TS      - Cloudflare account email address  
        CF_KEY_TS          - Cloudflare Global API Key
        CF_TOKEN_TS        - Cloudflare API token

    Example .cloudflare entries:
        CF_ACCOUNT_TS=example@example.com
        CF_KEY_TS=<global api key>
        # OR
        CF_TOKEN_PROD=<api token>
        CF_TOKEN_DEV=<dev api token>    

Version: $VERSION - DIR: $SCRIPT_DIR
"
}

# ==================================
# -- Arguments
# ==================================

# -- check if parameters are set
_debug "PARAMS: ${*}"
if [[ -z ${*} ]];then
	usage
	exit 1
fi

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -d|--debug)
    DEBUG="1"
    shift # past argument
    ;;
    -dr|--dryrun)
    DRYRUN="1"
    shift # past argument
    ;;
    -z|--zone)
    ZONE="$2"
    shift # past argument
    shift # past variable
    ;;
    -a|--account)
    CF_ACCOUNT_EMAIL="$2"
    shift # past argument
    shift # past variable
    ;;
    -t|--turnstile)
    TURNSTILE_ID="$2"    
    shift # past argument
    shift # past variable
    ;;
    -tn|--turnstile-name)
    TURNSTILE_NAME="$2"
    shift # past argument
    shift # past variable
    ;;
    -ak|--apikey)
    API_APIKEY="$2"
    shift # past argument
    shift # past variable  
    ;;
    -aid|--account-id)
    ACCOUNT_ID="$2"
    shift # past argument
    shift # past variable
    ;;
    create|--create)
    CMD="create_turnstile"
    shift # past argument
    ;;
    list|--list)
    CMD="list_turnstile"
    shift # past argument
    ;;
    delete|--delete)
    CMD="delete_turnstile"
    shift # past argument
    ;;
    test-creds|--test-creds)
    CMD="test-creds"
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
TOKEN_NAME=${2}


# -- Debug Enabled
if [[ $DEBUG == "1" ]]; then
    _debug "Debug enabled"
fi

# -- Initialize authentication
_debug "Initializing authentication"
if ! cf_auth_init; then
    _error "Authentication failed"
    exit 1
fi

# -- Run
_running "Running: $CMD"
# ===========================================
# -- Create Turnstile
# ===========================================
if [[ $CMD == 'create_turnstile' ]]; then
    [[ -z $ZONE ]] && { usage;_error "Please specify a domain name using -z"; exit 1;} # No domain, exit
    _running2 "Getting account id from zone ${ZONE}"
    if [[ -z $ACCOUNT_ID ]]; then
        _cf_zone_accountid $ZONE
        [[ $? -ne 0 ]] && { _error "Error getting account id from zone ${ZONE}"; exit 1;} # Error getting account id
        [[ -z $ACCOUNT_ID ]] && { usage;_error "No account id found"; exit 1;} # No account id, exit
    fi
        
    _running2 "Creating turnstile for $ZONE under $ACCOUNT_ID"
    [[ -z $TURNSTILE_NAME ]] && TURNSTILE_NAME="${ZONE}"
    create_turnstile $ZONE $ACCOUNT_ID $TURNSTILE_NAME
# ============================================
# -- List Turnstile
# ============================================
elif [[ $CMD == 'list_turnstile' ]]; then
    if [[ -n $ZONE ]]; then
        _running2 "Getting account id from zone ${ZONE}"        
        _cf_zone_accountid $ZONE
        [[ $? -ne 0 ]] && { _error "Error getting account id from zone ${ZONE}"; exit 1;} # Error getting account id
        [[ -z $ACCOUNT_ID ]] && { usage;_error "No account id found"; exit 1;} # No account id, exit
        _cf_list_turnstile $ACCOUNT_ID
    elif [[ -n $CF_ACCOUNT_EMAIL ]]; then
        ACCOUNT_ID=$(get_account_id_from_email $CF_ACCOUNT)
        [[ -z $ACCOUNT_ID ]] && { usage;_error "No account id found"; exit 1;} # No account id, exit
    else
        usage
        _error "No account id or zone id found"
        exit 1
    fi
    _running2 "Listing turnstiles for account: $ACCOUNT_ID"
    list_turnstile $ACCOUNT_ID
elif [[ $CMD == "delete_turnstile" ]]; then
    [[ -z $TURNSTILE_ID ]] && { usage;_error "Please specify a turnstile id using -t"; exit 1;} # No turnstile id, exit
    if [[ -n $ZONE ]]; then
        _running2 "Getting account id from zone ${ZONE}"        
        ACCOUNT_ID=$(_cf_zone_accountid $ZONE)
        [[ -z $ACCOUNT_ID ]] && { usage;_error "No account id found"; exit 1;} # No account id, exit
    elif [[ -n $CF_ACCOUNT_EMAIL ]]; then
        ACCOUNT_ID=$(get_account_id_from_email $CF_ACCOUNT)
        [[ -z $ACCOUNT_ID ]] && { usage;_error "No account id found"; exit 1;} # No account id, exit
    else
        usage
        _error "No account id or zone id found"
        exit 1
    fi
    _running2 "Deleting turnstile $TURNSTILE_ID for account: $ACCOUNT_ID"    
    delete_turnstile $ACCOUNT_ID $TURNSTILE_ID
elif [[ $CMD == 'test-creds' ]]; then
    [[ $2 ]] && test_creds $2 || test_creds
elif [[ $CMD == 'list-auth-profiles' ]]; then
    cf_auth_list_profiles
else
    usage
    _error "No command provided - $1"
    exit 1
fi