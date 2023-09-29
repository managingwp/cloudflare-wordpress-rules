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
REQUIRED_APPS=("jq" "column")

# -- Colors
NC='\e[0m' # No Color
CRED='\e[0;31m'
CGREEN='\e[0;32m'
CBLUEBG='\e[44m\e[97m'
CCYAN='\e[0;36m'
CDARK_GRAYBG='\e[100m\e[97m'

# ==================================
# -- Core Functions
# ==================================

# -- messages
_error () { echo -e "${CRED}** ERROR ** - ${*} ${NC}"; } # _error
_success () { echo -e "${CGREEN}** SUCCESS ** - ${*} ${NC}"; } # _success
_running () { echo -e "${CBLUEBG}${*}${NC}"; } # _running
_creating () { echo -e "${CDARK_GRAYBG}${*}${NC}"; }
_separator () { echo -e "${CYELLOWBG}****************${NC}"; }
_debug () {
    if [[ $DEBUG == "1" ]]; then
        echo -e "${CCYAN}** DEBUG ${*}${NC}"
    fi
}

# -- debug_jsons
_debug_json () {
    if [[ $DEBUG_JSON == "1" ]]; then
        echo -e "${CCYAN}** Outputting JSON ${*}${NC}"
        echo "${@}" | jq
    fi
}

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

# -- pre_flight_check - Check for .cloudflare credentials
function pre_flight_check () {
    if [[ -n $API_TOKEN ]]; then
        _running "Found \$API_TOKEN via CLI using for authentication/."        
        API_TOKEN=$CF_SPC_TOKEN
    elif [[ -n $API_ACCOUNT ]]; then
        _running "Found \$API_ACCOUNT via CLI using as authentication."                
        if [[ -n $API_APIKEY ]]; then
            _running "Found \$API_APIKEY via CLI using as authentication."                        
        else
            _error "Found API Account via CLI, but no API Key found, use -ak...exiting"
            exit 1
        fi
    elif [[ -f "$HOME/.cloudflare" ]]; then
            _debug "Found .cloudflare file."
            # shellcheck source=$HOME/.cloudflare
            source "$HOME/.cloudflare"
            
            # If $CF_SPC_ACCOUNT and $CF_SPC_KEY are set, use them.
            if [[ $CF_SPC_TOKEN ]]; then
                _debug "Found \$CF_SPC_TOKEN in \$HOME/.cloudflare"
                API_TOKEN=$CF_SPC_TOKEN
            elif [[ $CF_SPC_ACCOUNT && $CF_SPC_KEY ]]; then
                _debug "Found \$CF_SPC_ACCOUNT and \$CF_SPC_KEY in \$HOME/.cloudflare"
                API_ACCOUNT=$CF_SPC_ACCOUNT
                API_APIKEY=$CF_SPC_KEY
            else
                _error "No \$CF_TOKEN exiting"
                exit 1
            fi 
    else
        _error "Can't find \$HOME/.cloudflare, and no CLI options provided."
    fi

    # -- Required apps
    for app in "${REQUIRED_APPS[@]}"; do
        if ! command -v $app &> /dev/null; then
            _error "$app could not be found, please install it."
            exit 1
        fi
    done
}

# -- cf_api <$REQUEST> <$API_PATH>
function cf_api() {    
    # -- Run cf_api with tokens
    _debug "function:${FUNCNAME[0]}"
    _debug "Running cf_api() with ${*}"
    
    if [[ -n $API_TOKEN ]]; then
        _running "Running cf_api with Cloudflare Token"
        CURL_HEADERS=("-H" "Authorization: Bearer ${API_TOKEN}")
        _debug "Using \$API_TOKEN as token. \$CURL_HEADERS: ${CURL_HEADERS[*]}"
        REQUEST="$1"
        API_PATH="$2"
        CURL_OUTPUT=$(mktemp)    
    elif [[ -n $API_ACCOUNT ]]; then        
            _running "Running cf_api with Cloudflare API Key"
            CURL_HEADERS=("-H" "X-Auth-Key: ${API_APIKEY}" -H "X-Auth-Email: ${API_ACCOUNT}")
            _debug "Using \$API_APIKEY as token. \$CURL_HEADERS: ${CURL_HEADERS[*]}"
            REQUEST="$1"
            API_PATH="$2"
            CURL_OUTPUT=$(mktemp)
    else
        _error "No API Token or API Key found...major error...exiting"
        exit 1
    fi
	
    _debug "Running curl -s --request $REQUEST --url "${API_URL}${API_PATH}" "${CURL_HEADERS[*]}""
    CURL_EXIT_CODE=$(curl -s -w "%{http_code}" --request "$REQUEST" \
        --url "${API_URL}${API_PATH}" \
        "${CURL_HEADERS[@]}" \
        --output "$CURL_OUTPUT" "${EXTRA[@]}")
    API_OUTPUT=$(<"$CURL_OUTPUT")
    _debug_json "$API_OUTPUT"
    rm $CURL_OUTPUT    

		
	if [[ $CURL_EXIT_CODE == "200" ]]; then
	    MESG="Success from API: $CURL_EXIT_CODE"
        _debug "$MESG"
        _debug "$API_OUTPUT"    
	else
        MESG="Error from API: $CURL_EXIT_CODE"
        _error "$MESG"
        _debug "$API_OUTPUT"
    fi
}

# -- test_creds $ACCOUNT $API_KEY
function test_creds () {
    if [[ -n $API_TOKEN ]]; then
        _debug "function:${FUNCNAME[0]}"
        _running "Testing credentials via CLI"
        cf_api GET /client/v4/user/tokens/verify
        API_OUTPUT=$(echo $API_OUTPUT | jq '.messages[0].message' )
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

# -- get_zone_id
function get_zone_id () {
    _debug "function:${FUNCNAME[0]}"
    _running "Getting zone_id for ${DOMAIN_NAME}"
    cf_api GET /client/v4/zones?name=${DOMAIN_NAME}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        ZONE_ID=$(echo $API_OUTPUT | jq -r '.result[0].id' )
        if [[ $ZONE_ID != "null" ]]; then            
            _success "Got ZoneID ${ZONE_ID} for ${DOMAIN_NAME}"
        else
            _error "Couldn't get ZoneID, using -z to provide ZoneID or give access read:zone access to your token"
            echo "$MESG - $AP_OUTPUT"
            exit 1
        fi
    else
        _error "Couldn't get ZoneID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        echo "$MESG - $AP_OUTPUT"
        exit 1
    fi
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

# -- create_token
create_token () {
    _debug "function:${FUNCNAME[0]}" 
    echo "Adding persmissions to $DOMAIN_NAME aka $ZONE_ID"
    [[ -z $ZONE_ID ]] && get_zone_id || _debug "Using \$ZONE_ID via cli"
    ZONE_ID_JSON=("com.cloudflare.api.account.zone.${ZONE_ID}")
    EXTRA=(-H 'Content-Type: application/json' \
     --data '
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
    cf_api POST /client/v4/user/tokens $EXTRA
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        NEW_API_TOKEN=$(echo $API_OUTPUT | jq '.result.value')
        echo "New API Token -- ${TOKEN_NAME}: ${NEW_API_TOKEN}"
    else        
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
    -z|--zoneid)
    ZONE_ID="$2"
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
    create_token 
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