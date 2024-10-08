#!/bin/bash
# ---------------
# A script to create the necessary Cloudflare rules for the Super Page Cache for Cloudflare WordPress Plugin
# ---------------

# ==================================
# -- Variables
# ==================================
# Get Version from VERSION located in root directory
SCRIPT_NAME=cloudflare-spc
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
VERSION=$(cat "${SCRIPT_DIR}/VERSION")
API_URL="https://api.cloudflare.com"
DEBUG="0"
DRYRUN="0"

# ==================================================
# -- Libraries
# ==================================================
# shellcheck source=lib/cloudflare-lib.sh
source "${SCRIPT_DIR}/lib/cloudflare-lib.sh"
# shellcheck source=lib/core.sh
source "${SCRIPT_DIR}/lib/core.sh"


# TODO a method to be able to specify different credentials loaded from shell variable or .cloudflare file.

# ==================================
# -- Usage
# ==================================
usage () {
    echo \
"Usage: ./${SCRIPT_NAME}.sh [create <zone> <token-name> | list]

Creates appropriate api token and permissions for the Super Page Cache for Cloudflare WordPress plugin.

Commands:
    create-token <domain-name> <token-name> (-z|-a|-t|-ak)           - Creates a token called <token name> for <zone>, if <token-name> blank then (zone)-spc used
    list -t [token] | -a [account] -ak [api-key]                     - Lists account tokens.
    test-creds -t [token] | -a [account] -ak [api-key]               - Test credentials against Cloudflare API.
    test-token <token>                                               - Test created token against Cloudflare API.

Options:
    -z|--zone [zoneid]                - Set zoneid
    -a|--account [name@email.com]     - Cloudflare account email address
    -t|--token [token]                - API Token to use for creating the new token.
    -ak|--apikey [apikey]             - API Key to use for creating the new token.
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

# ==================================
# -- Functions
# ==================================

# -- test_creds $ACCOUNT $API_KEY
function test_creds () {
    if [[ -n $API_TOKEN ]]; then
        _debug "function:${FUNCNAME[0]}"
        _running "Testing credentials via CLI"
        cf_api GET /client/v4/user/tokens/verify
        API_OUTPUT=$(echo "$API_OUTPUT" | jq '.messages[0].message' )
        [[ $CURL_EXIT_CODE == "200" ]] && _success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
    elif [[ -n $API_APIKEY ]]; then
        _debug "function:${FUNCNAME[0]}"
        _running "Testing credentials via CLI"
        cf_api GET /client/v4/user
        API_OUTPUT=$(echo $API_OUTPUT | jq '.messages[0].message' )
        [[ $CURL_EXIT_CODE == "200" ]] && _success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
    else
        _error "No API Token or API Key found, exiting"
        exit 1
    fi
}

# -- test_api_token $TOKEN
function test-token () {    
    _debug "function:${FUNCNAME[0]}"
    _running "Testing token via CLI"        
    cf_api GET /client/v4/user/tokens/verify
    API_OUTPUT=$(echo $API_OUTPUT | jq '.messages[0].message' )
    [[ $CURL_EXIT_CODE == "200" ]] && _success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
}
 
# -- get_permissions
get_permissions () {
    _debug "Running get_permissions"
    cf_api GET /client/v4/user/tokens/permission_groups
}

# -- list_tokens
list_tokens () {
    _debug "Running list_tokens"
    cf_api GET /client/v4/user/tokens
}

# =================================================================================================
# -- create_token $DOMAIN $TOKEN_NAME
# =================================================================================================
create_token () {
    _debug "function:${FUNCNAME[0]}" 
    local DOMAIN_NAME=$1 TOKEN_NAME=$2 CF_ZONE_ID
    EXTRA=()

    _running2 "Getting Zone ID for $DOMAIN_NAME"
    CF_ZONE_ID="$(_get_zone_id $DOMAIN_NAME)"
    if [[ -z $CF_ZONE_ID ]]; then
        _error "No Zone ID found for $DOMAIN_NAME"
        exit 1
    else
        _success "Zone ID found for $DOMAIN_NAME: $CF_ZONE_ID"
    fi
    local ZONE_ID_JSON=("com.cloudflare.api.account.zone.${CF_ZONE_ID}")
    EXTRA=('
 {
 	"name": "'${DOMAIN_NAME}' '${TOKEN_NAME}'",
 	"policies": [
         {
 			"effect": "allow",
 			"resources": {
 				"com.cloudflare.api.account.*": "*"
 			},
 			"permission_groups": [{
 					"id": "e086da7e2179491d91ee5f35b3ca210a",
 					"name": "Workers Scripts Write"
 				},
 				{
 					"id": "c1fde68c7bcc44588cbb6ddbc16d6480",
 					"name": "Account Settings Read"
 				}
 			]
 		},
        {
 			"effect": "allow",
 			"resources": {
 				"'"${ZONE_ID_JSON[@]}"'": "*"
 			},
 			"permission_groups": [{
 					"id": "e17beae8b8cb423a99b1730f21238bed",
 					"name": "Cache Purge"
 				},
 				{
 					"id": "ed07f6c337da4195b4e72a1fb2c6bcae",
 					"name": "Page Rules Write"
 				},
 				{
 					"id": "3030687196b94b638145a3953da2b699",
 					"name": "Zone Settings Write"
 				},
 				{
 					"id": "e6d2666161e84845a636613608cee8d5",
 					"name": "Zone Write"
 				},
 				{
 					"id": "28f4b596e7d643029c524985477ae49a",
 					"name": "Workers Routes Write"
 				}
 			]
 		}
 	],
 	"condition": {}
 }')
    _debug "Extra: ${EXTRA[*]}"
    _running2 "Creating token ${TOKEN_NAME} for ${DOMAIN_NAME}"
    API_OUTPUT=$(_cf_api POST-JSON /client/v4/user/tokens "${EXTRA[@]}")
    
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        NEW_API_TOKEN=$(echo $API_OUTPUT | jq '.result.value')
        _success "New API Token -- ${TOKEN_NAME}: ${NEW_API_TOKEN}"
    else
        _error "Error creating token"
        echo "$API_OUTPUT"
        return 1
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
    -z|--zoneid)
    CF_ZONE_ID="$2"
    shift # past argument
    shift # past variable
    ;;
    -a|--account)
    API_ACCOUNT="$2"
    shift # past argument
    shift # past variable
    ;;
    -t|--token)
    API_TOKEN="$2"    
    shift # past argument
    shift # past variable
    ;;    
    -ak|--apikey)
    API_APIKEY="$2"
    shift # past argument
    shift # past variable  
    ;;  
    create-token|--create-token)
    CMD="create-token"
    shift # past argument
    ;;
    list|--list)
    CMD="list"
    shift # past argument
    ;;
    test-creds|--test-creds)
    CMD="test-creds"
    shift # past argument
    ;;
    test-token|--test-token)
    CMD="test-token"
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
if [[ $CMD == 'create-token' ]]; then
    [[ -z $DOMAIN_NAME ]] && { usage;_error "Please specify a domain name"; exit 1;} # No domain, exit
    [[ -z $TOKEN_NAME ]] && TOKEN_NAME="${DOMAIN_NAME}-spc" # Set default token.
    _running "Creating token for $DOMAIN_NAME"
    create_token $DOMAIN_NAME $TOKEN_NAME
elif [[ $CMD == 'list' ]]; then
    list_tokens
elif [[ $CMD == 'test-creds' ]]; then
    [[ $2 ]] && test_creds $2 || test_creds
elif [[ $CMD == 'test-token' ]]; then
    test_token $1
else
    usage
    _error "No command provided - $1"
    exit 1
fi