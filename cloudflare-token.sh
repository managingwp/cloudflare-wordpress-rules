#!/bin/bash
# =============================================================================
# cloudflare-token.sh
# =============================================================================

# ==================================
# -- Variables
# ==================================
# Get Version from VERSION located in root directory
SCRIPT_NAME="cloudflare-token"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
VERSION=$(cat "${SCRIPT_DIR}/VERSION")
DEBUG="0"
DRYRUN="0"

# ==================================================
# -- Libraries
# ==================================================
# shellcheck source=lib/cloudflare-lib.sh
source "${SCRIPT_DIR}/lib/cloudflare-lib.sh"
# shellcheck source=lib/core.sh
source "${SCRIPT_DIR}/lib/core.sh"
# shellcheck source=lib/core.sh
source "${SCRIPT_DIR}/lib/cloudflare-token.sh"


# ==================================
# -- Usage
# ==================================
usage () {
    echo \
"Usage: ./${SCRIPT_NAME}.sh [create <zone> <token-name> <type>| list]

Creates appropriate api token and permissions for the Super Page Cache for Cloudflare WordPress plugin.

Commands:
    create-token -d <domain-name> -tn <token-name> -tt <type> (-z|-a|-t|-ak)           - Creates a token called <token name> for <zone>, if <token-name> blank then (zone)-spc used
    list-tokens -a [account] -ak [api-key]                                             - Lists account tokens.
    test-creds -t [token] | -a [account] -ak [api-key]                                 - Test credentials against Cloudflare API.
    test-token -t <token>                                                                 - Test created token against Cloudflare API.

Options:
    -d|--domain [domain-name]         - Domain name
    -tn|--token-name [token-name]     - Token name
    -tt|--token-type [type]           - Token type

    -z|--zone [zoneid]                - Set zoneid for token creation
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