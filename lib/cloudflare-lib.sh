# ==================================================
# -- pre_flight_check - Check for .cloudflare credentials
# ==================================================
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
                _error "No \$CF_SPC_TOKEN exiting"
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

# ==================================================
# -- _cf_api <$METHOD> <$API_PATH> <${CURL_HEADERS[@]}>
# -- returns $CURL_EXIT_CODE and $API_OUTPUT
# ==================================================
function _cf_api() {
    # -- Run cf_api with tokens
    _debug "function:${FUNCNAME[0]}"
    _debug "Running _cf_api() with ${*}"

    local METHOD="${1^^}"
    shift
    local API_PATH="$1"
    shift
    #local QUERY_STRING
    #local RESULT_PAGE=1 RESULTS_PER_PAGE=50
    local CURL_OUTPUT
    declare -a CURL_OPTS
    CURL_OPTS=()
    CURL_OUTPUT=$(mktemp)

    _debug "METHOD: $METHOD API_PATH: $API_PATH CURL_OUTPUT: $CURL_OUTPUT"

    if [[ -n $API_TOKEN ]]; then
        _debug "Running cf_api with Cloudflare Token"
        CURL_HEADERS=("-H" "Authorization: Bearer ${API_TOKEN}")
        _debug "Using \$API_TOKEN as token. \$CURL_HEADERS: ${CURL_HEADERS[*]}"                
    elif [[ -n $API_ACCOUNT ]]; then        
            _debug "Running cf_api with Cloudflare API Key"
            CURL_HEADERS=("-H" "X-Auth-Key: ${API_APIKEY}" -H "X-Auth-Email: ${API_ACCOUNT}")
            _debug "Using \$API_APIKEY as token. \$CURL_HEADERS: ${CURL_HEADERS[*]}"        
    else
        _error "No API Token or API Key found...major error...exiting"
        exit 1
    fi

    # -- Check method and apply form type
    if [[ $METHOD = "POST" ]]; then
        _debug "Setting form type to form-data"
        CURL_OPTS+=(-H "Content-Type: multipart/form-data")
        FORMTYPE="form"               
    elif [[ $METHOD = "PATCH" ]]; then
        _debug "Setting form type to form-data"
        CURL_OPTS+=(-H "Content-Type: application/json")
        FORMTYPE="data"        
        # -- Pass JSON via CURL_OPTS        
    else
        CURL_OPTS+=(--get)
    fi

    # -- Process parameters
        while [ -n "$1" ]; do
            if [ ."$1" = .-- ]; then
                shift
                _debug "Parameters: ${*}"
                break
            else
                CURL_OPTS+=(--"$FORMTYPE" "$1")
            fi
            shift
        done     
	
    _debug "Running curl -s --url "${API_URL}${API_PATH}" "${CURL_HEADERS[*]} ${CURL_OPTS[*]}""
    set -x
    CURL_EXIT_CODE=$(curl -s -w "%{http_code}" --request "$METHOD" \
        --url "${API_URL}${API_PATH}" \
        "${CURL_HEADERS[@]}" \
        "${CURL_OPTS[@]}" \
        --output "$CURL_OUTPUT" "${EXTRA[@]}")
    set +x
    API_OUTPUT=$(<"$CURL_OUTPUT")
    _debug_json "$API_OUTPUT"
    rm $CURL_OUTPUT    

		
	if [[ $CURL_EXIT_CODE == "200" ]]; then
	    MESG="Success from API: $CURL_EXIT_CODE"
        _debug "$MESG"
        _debug "$API_OUTPUT"    
	else
        MESG="Error from API: $CURL_EXIT_CODE - $API_OUTPUT"
        _error "$MESG"
        _debug "$API_OUTPUT"
    fi
}


# ==================================================
# -- _get_zone_id $DOMAIN
# ==================================================
function _get_zone_id () {
    local DOMAIN=$1
	_debug "function:${FUNCNAME[0]}"
    _running2 "Getting zone_id for ${DOMAIN}"
    _cf_api GET /client/v4/zones?name=${DOMAIN}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        CF_ZONE_ID=$(echo $API_OUTPUT | jq -r '.result[0].id' )        
        if [[ $CF_ZONE_ID != "null" ]]; then            
            _running2 "Got ZoneID ${CF_ZONE_ID} for ${DOMAIN}"
        else
            _error "Couldn't get ZoneID, using -z to provide ZoneID or give access read:zone access to your token"
            echo "$MESG - $API_OUTPUT"
            exit 1
        fi
    else
        _error "Couldn't get ZoneID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        echo "$MESG - $AP_OUTPUT"
        exit 1
    fi
}

# ==================================================
# -- _convert_seconds $SECONDS
# -- returns $HUMAN_TIME
# ==================================================
function _convert_seconds () {
    local SECONDS=$1
    _debug "function:${FUNCNAME[0]}"
    _debug "Converting $SECONDS seconds to human readable time"
    local HUMAN_TIME
    HUMAN_TIME=$(date -d@${SECONDS} -u +%T)
    _debug "Converted $SECONDS seconds to $HUMAN_TIME"
    echo $HUMAN_TIME
}