#!/bin/bash
# ---------------
# A script to create the necessary Cloudflare rules for the Super Page Cache for Cloudflare WordPress Plugin
# ---------------

# ==================================
# -- Variables
# ==================================
VERSION=0.1.0
SCRIPT_NAME=cloudflare-spc
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
API_URL="https://api.cloudflare.com"
DEBUG="0"
DRYRUN="0"
REQUIRED_APPS=("jq" "column")

# -- Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
BLUEBG="\033[0;44m"
YELLOWBG="\033[0;43m"
GREENBG="\033[0;42m"
DARKGREYBG="\033[0;100m"
ECOL="\033[0;0m"

# -- _error
_error () {	echo -e "${RED}** ERROR ** - $@ ${ECOL}"; }
_success () { echo -e "${GREEN}** SUCCESS ** - $@ ${ECOL}"; }
_running () { echo -e "${BLUEBG}${@}${ECOL}"; }
_creating () { echo -e "${DARKGREYBG}${@}${ECOL}"; }
_separator () { echo -e "${YELLOWBG}****************${ECOL}"; }

_debug () {	
	if [[ $DEBUG == "1" ]]; then
		echo -e "${CYAN}** DEBUG: $@${ECOL}"
	fi
}

# -- debug_jsons
_debug_json () {
    if [[ $DEBUG_JSON == "1" ]]; then
        echo -e "${CCYAN}** Outputting JSON ${*}${NC}"
        echo "${@}" | jq
    fi
}

# -- Check for .cloudflare credentials
if [ ! -f "$HOME/.cloudflare" ];then
		echo "No .cloudflare file."
	if [ -z "$CF_ACCOUNT" ];then
		_error "No \$CF_ACCOUNT set."
		HELP usage
		_die
	fi
	if [ -z "$CF_4TOKEN" ]; then
		_error "No \$CF_4TOKEN set."
		HELP usage
		_die
	fi
else
	_debug "Found .cloudflare file."
	source $HOME/.cloudflare
	_debug "Sourced CF_ACCOUNT: $CF_ACCOUNT CF_4TOKEN: $CF_4TOKEN"

        if [ -z "$CF_ACCOUNT" ]; then
                _error "No \$CF_ACCOUNT set in config."
                HELP usage
				_die
        fi
        if [ -z "$CF_4TOKEN" ]; then
                _error "No \$CF_4TOKEN set in config.

        $USAGE"
        fi
fi

# -- parse args
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    create|--create)
    CMD="create"
    shift # past argument
    ;;
    list|--list)
    CMD="list"
    shift # past argument
    ;;
    verify|--verify)
    CMD="verify"
    shift # past argument
    ;;
    -d|--debug)
    DEBUG="1"
    shift # past argument
    ;;
    -z|--zone)
    DOMAIN_NAME="$2"
    shift # past argument
    shift # past value
    ;;
    -t|--token)
    TOKEN_NAME="$2"
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# Set API token and email
EMAIL=$CF_ACCOUNT

# -- usage
usage () {
    echo \
"Usage: ./cloudflare-spc.sh [create <zone> <token-name> | list]

Creates appropriate api token and permissions for the Super Page Cache for Cloudflare WordPress plugin.

Commands: 
    create -z <zone> -t <token-name>         - Creates a token called <token name> for <zone>
    list                                     - Lists account tokens.
    veriy <token>                            - Verify token.

Options:
    -z          - Zone as domain name.
    -t          - Token name for new token
    -d          - Debug
    
Environment variables:
    CF_ACCOUNT   -  Cloudflare Email address
    CF_4TOKEN    -  Cloudflare API token

Configuration file for credentials:
    Create a file in \$HOME/.cloudflare with both CF_ACCOUNT and CF_4TOKEN defined.

    CF_ACCOUNT=example@example.com
    CF_4TOKEN=<token>
    "
}

get_zone_id () {
    curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN_NAME}" \
    -H "Authorization: Bearer ${CF_4TOKEN}" \
    -H "Content-Type: application/json"
}

# -- get_zone_id
function get_zone_id () {
    _debug "function:${FUNCNAME[0]}"
    _running "Getting zone_id for ${DOMAIN_NAME}"
    cf_api GET /client/v4/zones?name=${DOMAIN_NAME}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        ZONE_ID=$(echo $API_OUTPUT | jq -r '.result[0].id' )
        _success "Got ZoneID ${ZONE_ID} for ${DOMAIN_NAME}"        
    else
        _error "Couldn't get ZoneID, using -z to provide ZoneID or give access read:zone access to your token"
        echo "$MESG - $AP_OUTPUT"
        exit 1
    fi
}

# get_permissions
get_permissions () {
    _debug "Running get_permissions"
    curl -s -X GET \
    "https://api.cloudflare.com/client/v4/user/tokens/permission_groups" \
    -H "Authorization: Bearer ${CF_4TOKEN}" \
    -H "Content-Type: application/json"
}

# list_tokens
list_tokens () {
    _debug "Running list_tokens"
    curl -s -X GET \
    "https://api.cloudflare.com/client/v4/user/tokens" \
    -H 'Authorization: Bearer '${CF_4TOKEN}'' \
    -H 'Content-Type: application/json' | jq
}

# verify_tokens
verify_tokens () {
	curl -s -X GET \
	"https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer ${1}"
}

# -- create_token
create_token () {
    _debug "function:${FUNCNAME[0]}" 
    echo "Adding persmissions to $DOMAIN_NAME aka $ZONE_ID"
	
	_debug 'curl -s -X POST "https://api.cloudflare.com/client/v4/user/tokens" \
     -H "Authorization: Bearer '"${CF_4TOKEN}'" \
     -H "Content-Type: application/json"
	
    NEW_API_TOKEN_OUTPUT=$(curl -s -X POST "https://api.cloudflare.com/client/v4/user/tokens" \
     -H "Authorization: Bearer ${CF_4TOKEN}" \
     -H "Content-Type: application/json" \
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

# -------
# -- Main
# -------

# -- list
if [[ $CMD == 'list' ]]; then  
    list_tokens
# -- verify
elif [[ $CMD == 'verify' ]]; then
	if [[ -z $1 ]]; then
		_error "Please provide token to verify"
		exit 1
	else
		verify_token
	fi
# -- create
elif [[ $CMD == 'create' ]]; then
    if [[ -z $DOMAIN_NAME ]]; then
    	_error "Specify zone using -z"
    	exit 1
    elif [[ -z $TOKEN_NAME ]]; then
		_error "Specify token name using -t"
        usage
        exit 1
    else
	    ZONE_ID=$(get_zone_id | jq -r '.result[0].id')
	    _debug "\$ZONE_ID = $ZONE_ID"
	    create_token
	fi
else
    usage
    _error "Unknown command $1"
    exit 1
fi