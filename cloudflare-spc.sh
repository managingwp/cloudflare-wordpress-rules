#!/usr/bin/env bash
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
FIRST_ONE="0"
CSV="0"

# ==================================
# -- Include cf-inc.sh and cf-api-inc.sh
# ==================================
source "$SCRIPT_DIR/cf-inc.sh"
source "$SCRIPT_DIR/cf-inc-api.sh"
source "$SCRIPT_DIR/cf-inc-spc.sh"

# ==================================
# -- Usage
# ==================================
usage () {
    echo \
"Usage: ./${SCRIPT_NAME}.sh -c <command> -d <domain> -tn <token-name> 

Creates appropriate api token and permissions for the Super Page Cache for Cloudflare WordPress plugin.

Commands:
    create -d <domain> -tn <token-name>             - Creates a token called <token name> for <zone>, if <token-name> blank then (zone)-spc used
    create-file <file>                              - Creates tokens for all domains in <file> (one domain per line)
    list -d <domain>                                - Lists account tokens.
    
    token-exists -d <domain> -tn <token-name>       - Check if token exists for domain
    test-token <token>                              - Test created token against Cloudflare API.
    test-perms -d <domain> -ao                     - Check permissions for account owned token

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
    --first-one                                - Only run first action in automation steps like create-file
    --csv                                      - CSV output

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
    --first-one)
    FIRST_ONE=1
    shift # past argument
    ;;
    --csv)
    QUIET="1"
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
    _cf_spc_create_token "$DOMAIN_NAME" "$TOKEN_NAME"
elif [[ $CMD == 'create-file' ]]; then
    FILE="$1"
    [[ -z $FILE ]] && { usage;_error "Please specify a file"; exit 1;} # No file, exit
    [[ ! -f $FILE ]] && { usage;_error "File not found: $FILE"; exit 1;} # File not found, exit
    _debug "FILE: $FILE"        
    _running "Creating tokens for all domains in $FILE"
    echo
    cat "$FILE"
    echo
    
    _running2 "Are you sure you want to create tokens for all domains in $FILE? (y/n)"
    read -r -p "Are you sure? (y/n) " -n 1 -s
    echo  
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        _success "Creating tokens for all domains in $FILE"
        _debug "User confirmed"        
    else
        _error "Existing"
        _debug "User cancelled"
        exit 1
    fi
    [[ $? -ne 0 ]] && { _error "Aborting"; exit 1;} # User cancelled, exit
    
    # -- Look through domains in file
    while IFS= read -r DOMAIN_NAME; do
        _running "Creating token for $DOMAIN_NAME"
        [[ -z $DOMAIN_NAME ]] && { _error "No domain name found in file"; continue;} # No domain name, skip        
        [[ $DOMAIN_NAME =~ ^#.*$ ]] && { _debug "Skipping comment: $DOMAIN_NAME"; continue;} # Skip comments
        _debug "Creating toking for $DOMAIN_NAME"
        _cf_spc_create_token "$DOMAIN_NAME" 
        if [[ $? -ne 0 ]]; then
          _error "Error creating token for $DOMAIN_NAME"; 
          [[ $FIRST_ONE == 1 ]] && { _debug "First one only"; exit 1;} # Only run first action
          continue
        fi
        [[ $FIRST_ONE == 1 ]] && { _debug "First one only"; exit 1;} # Only run first action
    done < "$1"
    _running2 "Finished creating tokens for all domains in $FILE"
# ==================================
# -- List tokens
# ==================================
elif [[ $CMD == 'list' ]]; then
    list_tokens $DOMAIN_NAME
# ==================================
# -- token-exists
# ==================================
elif [[ $CMD == 'token-exists' ]]; then
    [[ -z $DOMAIN_NAME ]] && { usage;_error "Please specify a domain name"; exit 1;} # No domain, exit
    [[ -z $TOKEN_NAME ]] && { usage;_error "Please specify a token name"; exit 1;} # No token name, exit
    _cf_spc_token_exists "$DOMAIN_NAME" "$TOKEN_NAME"
# ==================================
# -- test-token
# ===================================
elif [[ $CMD == 'test-token' ]]; then
    [[ -z $DOMAIN_NAME ]] && { usage;_error "Please specify a domain name"; exit 1;} # No domain, exit
    [[ -z $TOKEN_NAME ]] && { usage;_error "Please specify a token name"; exit 1;} # No token name, exit
    _cf_spc_test_token "$DOMAIN_NAME" "$TOKEN_NAME"
# ==================================
# -- test-perms
# ==================================
elif [[ $CMD == 'test-perms' ]]; then
    [[ -z $DOMAIN_NAME ]] && { usage;_error "Please specify a domain name"; exit 1;} # No domain, exit
    _cf_spc_test_perms "$DOMAIN_NAME" "$ACCOUNT_OWNED"
else
    usage
    if [[ -z $CMD ]]; then
        _error "No command provided"
    else
      _error "Command not found: $CMD"
    fi
    exit 1
fi