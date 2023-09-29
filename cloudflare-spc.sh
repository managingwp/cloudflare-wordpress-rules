#!/bin/bash

# ---------------
# A script to create the necessary Cloudflare rules for the Super Page Cache for Cloudflare WordPress Plugin
# ---------------

# -- Variables
VERSION=0.0.1
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SCRIPT_NAME="cloudflare-spc.sh"
DEBUG="0"
DRYRUN="0"

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
_error () {	echo -e "${RED}** ERROR ** - $@ ${ECOL}" }
_success () { echo -e "${GREEN}** SUCCESS ** - $@ ${ECOL}" }
_running () { echo -e "${BLUEBG}${@}${ECOL}" }
_creating () { echo -e "${DARKGREYBG}${@}${ECOL}" }
_separator () { echo -e "${YELLOWBG}****************${ECOL}" }
_debug () {	
	if [[ $DEBUG == "1" ]]; then
		echo -e "${CYAN}** DEBUG: $@${ECOL}"
	fi
}
_debug_json () {
    if [ -f $SCRIPT_DIR/.debug ]; then
        echo $@ | jq
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
	if [ -z "$CF_TOKEN" ]; then
		_error "No \$CF_TOKEN set."
		HELP usage
		_die
	fi
else
	_debug "Found .cloudflare file."
	source $HOME/.cloudflare
	_debug "Sourced CF_ACCOUNT: $CF_ACCOUNT CF_TOKEN: $CF_TOKEN"

        if [ -z "$CF_ACCOUNT" ]; then
                _error "No \$CF_ACCOUNT set in config."
                HELP usage
				_die
        fi
        if [ -z "$CF_TOKEN" ]; then
                _error "No \$CF_TOKEN set in config.

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
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# Set API token and email
EMAIL=$CF_ACCOUNT

# Set zone ID for domain.com
DOMAIN_NAME=${1}
TOKEN_NAME=${2}
echo "args: $@"

usage () {
    echo "Usage: ./cloudflare-api.sh create <zone> <token-name> | list"
}

get_zone_id () {
    curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN_NAME}" \
    -H "Authorization: Bearer ${CF_TOKEN}" \
    -H "Content-Type: application/json"
}


get_permissions () {
    curl -s -X GET \
    "https://api.cloudflare.com/client/v4/user/tokens/permission_groups" \
    -H "Authorization: Bearer ${CF_TOKEN}" \
    -H "Content-Type: application/json"
}

list_tokens () {
    curl -s -X GET \
    "https://api.cloudflare.com/client/v4/user/tokens" \
    -H 'Authorization: Bearer '${CF_TOKEN}'' \
    -H 'Content-Type: application/json'
}

create_token () {
    echo "Adding persmissions to $DOMAIN_NAME aka $ZONE_ID"

    NEW_API_TOKEN_OUTPUT=$(curl -s -X POST "https://api.cloudflare.com/client/v4/user/tokens" \
     -H "Authorization: Bearer ${CF_TOKEN}" \
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
 				"com.cloudflare.api.account.zone.'${ZONE_ID}'": "*"			
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

    echo "---------------------"
    echo $NEW_API_TOKEN_OUTPUT
    echo "---------------------"
    NEW_API_TOKEN=$(echo $NEW_API_TOKEN_OUTPUT | jq '.result.value')
    echo "New API Token -- ${TOKEN_NAME}: ${NEW_API_TOKEN}"
}


if [[ $CMD == 'list' ]]; then  
    list_tokens
elif [[ $CMD == 'create' ]]; then
    if [[ -z $DOMAIN_NAME ]] || [[ -z $TOKEN_NAME ]]; then
        usage
        exit 1
    fi
    ZONE_ID=$(get_zone_id | jq -r '.result[0].id')
    create_token
else
    usage
    exit 1
fi