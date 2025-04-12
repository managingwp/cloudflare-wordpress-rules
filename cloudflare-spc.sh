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
DEBUG="0"
DRYRUN="0"
QUIET="0"

# ==================================
# -- Include cf-inc.sh and cf-api-inc.sh
# ==================================
source "$SCRIPT_DIR/cf-inc.sh"
source "$SCRIPT_DIR/cf-inc-api.sh"

# ==================================
# -- Usage
# ==================================
usage () {
    echo \
"Usage: ./${SCRIPT_NAME}.sh -c <command> -d <domain> -tn <token-name> 

Creates appropriate api token and permissions for the Super Page Cache for Cloudflare WordPress plugin.

Commands:
    create -d <domain-name> -tn <token-name>        - Creates a token called <token name> for <zone>, if <token-name> blank then (zone)-spc used
    list -d <domain-name>                           - Lists account tokens.
    test-token <token>                              - Test created token against Cloudflare API.

Options:
    -d|--domain [domain name]              - Set zoneid
    -tn|--token-name [token name]          - Set token name

Additional Options:
    -ao|--account-owned                        - Account owned token
    -ae|--account-email [name@email.com]       - Cloudflare account email address
    -ak|--api-key [apikey]                     - API Key to use for creating the new token.
    -at|--account-token [token]                - API Token to use for creating the new token.
    --debug                                    - Debug mode
    --debug-json                               - Debug JSON output
    --dryrun                                   - Dry run mode

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

# =============================================================================
# -- Functions
# =============================================================================

# ==================================
# -- list_tokens $DOMAIN_NAME
# ===================================
list_tokens () {
    _debug "Running list_tokens"
    if [[ $ACCOUNT_OWNED ]]; then        
        _running2 "Listing tokens for $DOMAIN_NAME"        
        _cf_zone_accountid $DOMAIN_NAME
        _running3 "Found AccountID: $ACCOUNT_ID for $DOMAIN_NAME"
        cf_api GET /client/v4/accounts/${ACCOUNT_ID}/tokens
        echo "$API_OUTPUT" | jq '.result[] | {id: .id, name: .name, created_at: .created_at, modified_at: .modified_at}'
    else
        _running2 "Listing tokens for user"
        cf_api GET /client/v4/user/tokens
        echo "$API_OUTPUT" | jq '.result[] | {id: .id, name: .name, created_at: .created_at, modified_at: .modified_at}'
    fi
}

# ==================================
# -- create_token $ZONE_ID $DOMAIN_NAME $TOKEN_NAME
# ==================================
create_token () {
    _debug "function:${FUNCNAME[0]}"
    local ZONE_ID=${1}
    local DOMAIN_NAME=${2}
    local TOKEN_NAME=${3}
    
    _debug "Creating token for $DOMAIN_NAME with id $ZONE_ID"
    if [[ -n $ACCOUNT_OWNED ]]; then
      if [[ -z $ACCOUNT_OWNED_ID ]]; then
        _running2 "Getting account id for account owned"
        ACCOUNT_OWNED_ID=$(_cf_get_account_id_from_zone $ZONE_ID)
        if [[ -z $ACCOUNT_OWNED_ID ]]; then
          _error "No account id found for $ZONE_ID"
          exit 1
        fi
      fi

      _debug "Creating token for id $ZONE_ID using account id $ACCOUNT_OWNED_ID"
      CF_API_ACCOUNT="com.cloudflare.api.account.${ACCOUNT_OWNED_ID}\":\"*"

    else
        _running "Creating token for user"
        CF_API_ACCOUNT="com.cloudflare.api.account.*\":\"*"
    fi
    
    _running2 "Adding persmissions to $DOMAIN_NAME aka $ZONE_ID"    
    ZONE_ID_JSON=("com.cloudflare.api.account.zone.${ZONE_ID}")
    EXTRA=(-H 'Content-Type: application/json' \
     --data '
 {
  "name": "'${DOMAIN_NAME}' '${TOKEN_NAME}'",
  "policies": [
    {
      "effect": "allow",
      "resources": {
        "'${CF_API_ACCOUNT}'"
      },
      "permission_groups": [
        {
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
        "'${ZONE_ID_JSON[@]}'": "*"
      },
      "permission_groups": [
        {
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
        },
        {
          "id": "9c88f9c5bce24ce7af9a958ba9c504db",
          "name": "Zone Analytics Read"
        },
        {
          "id": "c8fed203ed3043cba015a93ad1616f1f",
          "name": "Zone Read"
        },
        {
          "id": "3030687196b94b638145a3953da2b699",
          "name": "Zone Settings Write"
        },
        {
          "id": "82e64a83756745bbbb1c9c2701bf816b",
          "name": "DNS Read"
        },
        {
          "id": "e17beae8b8cb423a99b1730f21238bed",
          "name": "Zone Cache Purge"
        },
        {
          "id": "9ff81cbbe65c400b97d92c3c1033cab6",
          "name": "Zone Cache Rules Edit"
        },
        {
          "id": "0ac90a90249747bca6b047d97f0803e9",
          "name": "Zone Transform Rules Write"
        }
      ]
    }
  ],
  "condition": {}
}')
    if [[ -n $ACCOUNT_OWNED ]]; then
        cf_api POST /client/v4/accounts/${ACCOUNT_OWNED_ID}/tokens "${EXTRA[@]}"
    else
        cf_api POST /client/v4/user/tokens "${EXTRA[@]}"
    fi
    
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
    -c|--command)
    CMD="$2"
    shift # past argument
    shift # past variable
    ;;
    -d|--domain)
    DOMAIN_NAME="$2"
    shift # past argument
    shift # past variable
    ;;
    -tn|--token-name)
    TOKEN_NAME="$2"
    shift # past argument
    shift # past variable
    ;;
    -ao)     
    ACCOUNT_OWNED="1"
    shift # past argument
    ;;    
    --aoid)
    ACCOUNT_OWNED_ID="$2"
    shift # past argument
    shift # past variable
    ;;
    -ae|--account-email)
    API_ACCOUNT="$2"
    shift # past argument
    shift # past variable
    ;;
    -at|--account-token)
    API_TOKEN="$2"    
    shift # past argument
    shift # past variable
    ;;    
    -ak|--apikey)
    API_APIKEY="$2"
    shift # past argument
    shift # past variable  
    ;;
    --debug)
    DEBUG="1"
    shift # past argument
    ;;
    --debug-json)
    DEBUG="1"
    DEBUG_CURL_OUTPUT="1"
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

# -- Debug Enabled
if [[ $DEBUG == "1" ]]; then
    _debug "Debug enabled"
fi

# Get zone ID for domain.com and set TOKEN_NAME
_running "Running $CMD on $DOMAIN_NAME"

# -- pre-flight check
_debug "Pre-flight_check"
_pre_flight_check CF_SPC_

# -- Run
if [[ $CMD == 'create' ]]; then        
    [[ -z $DOMAIN_NAME ]] && { usage;_error "Please specify a domain name"; exit 1;} # No domain, exit    
    ZONE_ID=$(_cf_zone_id $DOMAIN_NAME) # Get zone id
    _debug "ZONE_ID: $ZONE_ID"    
    [[ -z $ZONE_ID ]] && { usage;_error "No zone id found for $DOMAIN_NAME"; exit 1;} # No zone id, exit
    
    _running2 "Creating token for $DOMAIN_NAME with id $ZONE_ID"
    [[ -z $TOKEN_NAME ]] && TOKEN_NAME="${DOMAIN_NAME}-spc" # Set default token.
    create_token $ZONE_ID $DOMAIN_NAME $TOKEN_NAME  
elif [[ $CMD == 'list' ]]; then
    list_tokens $DOMAIN_NAME
elif [[ $CMD == 'test-creds' ]]; then
    [[ $2 ]] && test_creds $2 || test_creds
elif [[ $CMD == 'test-token' ]]; then
    test_token $1
else
    usage
    if [[ -z $CMD ]]; then
        _error "No command provided"
    else
      _error "Command not found: $CMD"
    fi
    exit 1
fi