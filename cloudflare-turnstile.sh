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
ZONE_ID=""
TURNSTILE_ID=""
ZONE=""


# -- Include cf-inc.sh
source "$SCRIPT_DIR/cf-inc.sh"
source "$SCRIPT_DIR/cf-api-inc.sh"

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

Options:
    -z|--zone [domain name]                - Zone domain name
    -a|--account [name@email.com]          - Cloudflare account email address
    -t|--turnstile [turnstile sitekey]     - Turnstile Sitekey
    -tn|--turnstile-name [name]            - Turnstile Name
    -ak|--apikey [apikey]                  - API Key to use for creating the new turnstile.
    -d|--debug                             - Debug mode
    -dr|--dryrun                           - Dry run mode

Environment variables:
    CF_TS_ACCOUNT      - Cloudflare account email address
    CF_TS_KEY          - Cloudflare Global API Key
    CF_TS_TOKEN        - Cloudflare API token.

Configuration file for credentials:
    Create a file in \$HOME/.cloudflare with both CF_TS_ACCOUNT and CF_TS_KEY defined or CF_TS_TOKEN. Only use a KEY or Token, not both.

    CF_TS_ACCOUNT=example@example.com
    CF_TS_KEY=<global api key>    

Version: $VERSION - DIR: $SCRIPT_DIR
"
}

# ==================================
# -- Functions
# ==================================

# ==================================
# -- create_turnstile $DOMAIN_NAME $ACCOUNT_ID $TURNSTILE_NAME
# -- Create a turnstile id for site.
# ==================================
#curl https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/challenges/widgets \
#    -H 'Content-Type: application/json' \
#    -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
#    -H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
#    -d '{
#      "domains": [
#        "203.0.113.1",
#        "cloudflare.com",
#        "blog.example.com"
#      ],
#      "mode": "non-interactive",
#      "name": "blog.cloudflare.com login form",
#      "clearance_level": "no_clearance"
#    }'
#
function create_turnstile () {
    DOMAIN_NAME=$1
    ACCOUNT_ID=$2
    TURNSTILE_NAME=$3
    _debug "function:${FUNCNAME[0]}"    
    EXTRA=(-H 'Content-Type: application/json' \
     --data 
    '{
        "domains": [
            "'$DOMAIN_NAME'"
        ],
        "mode": "non-interactive",
        "name": "'$TURNSTILE_NAME'",
        "clearance_level": "no_clearance"
        }')
    cf_api POST /client/v4/accounts/${ACCOUNT_ID}/challenges/widgets $EXTRA
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        json2_keyval $API_OUTPUT        
    else        
        echo "$MESG - $API_OUTPUT"
        exit 1
    fi
}

# ==================================
# -- list_turnstile $ACCOUNT_ID
# -- List all turnstile tokens
# ==================================
function list_turnstile () {
    local ACCOUNT_ID=$1
    _debug "function:${FUNCNAME[0]}"    
    cf_api GET /client/v4/accounts/${ACCOUNT_ID}/challenges/widgets
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        json2_keyval_array "$API_OUTPUT"
    else
        _error "Couldn't get turnstile list, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        echo "$MESG - $API_OUTPUT"
        exit 1
    fi
}

# ==================================
# -- delete_turnstile $ACCOUNT_ID $TURNSTILE_ID
# -- Delete a turnstile token
# ==================================
function delete_turnstile () {
    local ACCOUNT_ID=$1
    local TURNSTILE_ID=$2
    _debug "function:${FUNCNAME[0]}"    
    cf_api DELETE /client/v4/accounts/${ACCOUNT_ID}/challenges/widgets/${TURNSTILE_ID}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _running "Deleted turnstile $TURNSTILE_ID"
    else
        _error "Couldn't delete turnstile, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        echo "$MESG - $API_OUTPUT"
        exit 1
    fi
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

# -- pre-flight check
_debug "Pre-flight_check"
[[ $CMD != "test-token" ]] && pre_flight_check

# -- Run
_running "Running: $CMD"
if [[ $CMD == 'create_turnstile' ]]; then
    [[ -z $ZONE ]] && { usage;_error "Please specify a domain name using -z"; exit 1;} # No domain, exit
    _running2 "Getting account id from zone ${ZONE}"
    ACCOUNT_ID=$(get_account_id_from_domain $ZONE)
    [[ -z $ACCOUNT_ID ]] && { usage;_error "No account id found"; exit 1;} # No account id, exit
    _running2 "Creating turnstile for $ZONE under $ACCOUNT_ID"
    [[ -z $TURNSTILE_NAME ]] && TURNSTILE_NAME="${ZONE}"
    create_turnstile $ZONE $ACCOUNT_ID $TURNSTILE_NAME
elif [[ $CMD == 'list_turnstile' ]]; then
    if [[ -n $ZONE ]]; then
        _running2 "Getting account id from zone ${ZONE}"        
        ACCOUNT_ID=$(get_account_id_from_domain $ZONE)
        [[ -z $ACCOUNT_ID ]] && { usage;_error "No account id found"; exit 1;} # No account id, exit
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
        ACCOUNT_ID=$(get_account_id_from_domain $ZONE)
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
else
    usage
    _error "No command provided - $1"
    exit 1
fi