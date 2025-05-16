#!/usr/bin/env bash
# =================================================================================================
# cf-api-inc v1.6.0
# =================================================================================================

# =====================================
# -- Variables
# =====================================
API_LIB_VERSION="1.5"
API_URL="https://api.cloudflare.com"
DEBUG_CURL_OUTPUT="0"
declare -a cf_api_functions
echo "Cloudflare API Library v${API_LIB_VERSION}"

# =============================================================================
# -- Core Functions
# =============================================================================

# =====================================
# -- _list_core_functions
# -- List all core functions
# =====================================
cf_api_functions["_list_core_functions"]="List all core functions"
function _list_core_functions () {
    _running "Listing all core functions with descriptions"
    # Print header
    printf "%-40s | %-40s | %s\n" "Function" "Description" "Count"
    printf "%s-+-%s-+-%s\n" "$(printf '%0.s-' {1..40})" "$(printf '%0.s-' {1..40})" "$(printf '%0.s-' {1..10})"
    
    # Loop through array, printing key and value
    for FUNC_NAME in "${!cf_api_functions[@]}"; do
        # -- Count how many times the function is used in the script
        FUNC_COUNT=$(grep -c "$FUNC_NAME" "$SCRIPT_DIR"/*.sh)
        DESCRIPTION="${cf_api_functions[$FUNC_NAME]}"
        printf "%-40s | %-40s | %s\n" "$FUNC_NAME" "$DESCRIPTION" "$FUNC_COUNT"
    done
}

# =============================================================================
# -- Cloudflare API Functions
# =============================================================================

# =====================================
# -- cf_api <$REQUEST> <$API_PATH> [--paginate] [--all-pages] "${EXTRA[@]}"
# -- Run cf_api request and return output via $API_OUTPUT
# -- Run cf_api request and return exit code via $CURL_EXIT_CODE
# =====================================
cf_api_functions["cf_api"]="Run cf_api request"
function cf_api() {
    # -- Run cf_api with tokens
    _debug "function:${FUNCNAME[0]} - ${*}"

    # -- Pagination
    local PAGINATE=0
    local ALL_PAGES=0
    local PAGE=1
    local PER_PAGE=50
    # shellcheck disable=SC2034
    local HAS_MORE=false
    # shellcheck disable=SC2034
    local COMBINED_RESULTS=""
    local API_PATH=""
    local REQUEST=""
    local CURL_HEADERS=()
    local args=()

    # Parse arguments for pagination options
    for arg in "$@"; do
        case "$arg" in
            --paginate)
                PAGINATE=1
                ;;
            --all-pages)
                PAGINATE=1
                # shellcheck disable=SC2034
                ALL_PAGES=1
                ;;
            --page=*)
                PAGE="${arg#*=}"
                PAGINATE=1
                ;;
            --per-page=*)
                PER_PAGE="${arg#*=}"
                PAGINATE=1
                ;;
            *)
                args+=("$arg")
                ;;
        esac
    done
    _debug "ARG: ${args[*]}"

    # Set pagination parameters
    REQUEST="${args[0]}"
    API_PATH="${args[1]}"
    EXTRA=("${args[@]:2}")

    # Add pagination parameters if needed
    if [[ $PAGINATE -eq 1 ]]; then
        # Check if API_PATH already has query parameters
        if [[ "$API_PATH" == *\?* ]]; then            
            API_PATH="${API_PATH}&page=${PAGE}&per_page=${PER_PAGE}"
        else
            API_PATH="${API_PATH}?page=${PAGE}&per_page=${PER_PAGE}"
        fi
    fi
    _debug "API_PATH: $API_PATH"

    # -- Create headers for curl
    if [[ -n $API_TOKEN ]]; then
        CURL_HEADERS=("-H" "Authorization: Bearer ${API_TOKEN}")
        _debug "Using \$API_TOKEN as 'Authorization: Bearer'. \$CURL_HEADERS: ${CURL_HEADERS[*]}"        
    elif [[ -n $API_ACCOUNT ]]; then
        CURL_HEADERS=("-H" "X-Auth-Key: ${API_APIKEY}" -H "X-Auth-Email: ${API_ACCOUNT}")
        _debug "Using \$API_APIKEY as X-Auth-Key. \$CURL_HEADERS: ${CURL_HEADERS[*]}"        
    else
        _error "No API Token or API Key found...major error...exiting"
        exit 1
    fi

    # -- Create temporary file for curl output
    CURL_OUTPUT=$(mktemp)

    # -- Start API Call
    _debug "Running curl -s --request $REQUEST --url "${API_URL}${API_PATH}" "${CURL_HEADERS[*]}" --output $CURL_OUTPUT ${EXTRA[*]}"
    [[ $DEBUG == "1" ]] && set -x
    CURL_EXIT_CODE=$(curl -s --output "$CURL_OUTPUT" -w "%{http_code}" --request "$REQUEST" \
        --url "${API_URL}${API_PATH}" \
        "${CURL_HEADERS[@]}" \
        "${EXTRA[@]}")
    [[ $DEBUG == "1" ]] && set +x
    API_OUTPUT=$(<"$CURL_OUTPUT")
    _debug "CURL_EXIT_CODE: $CURL_EXIT_CODE"
    _debug_json "$API_OUTPUT"
    rm "$CURL_OUTPUT"

    # -- Check for more pages
    API_PAGES=$(echo $API_OUTPUT | jq -r '.result_info | select(.total_pages > .page).total_pages')
    if [[ $API_PAGES -gt 1 ]]; then
        _debug "More pages found: $API_PAGES"
    fi

    # -- Check for errors
	if [[ $CURL_EXIT_CODE == "200" ]]; then
	    MESG="Success from API: $CURL_EXIT_CODE"
        _debug "$MESG"
        _debug "$API_OUTPUT"
	else
        MESG="Error from API: $CURL_EXIT_CODE"
        _error "$MESG"
        parse_cf_error "$API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- parse_cf_error $API_OUTPUT
# =====================================
cf_api_functions["parse_cf_error"]="Parse Cloudflare API Error"
parse_cf_error () {
    API_OUTPUT=$1
    _debug "Running parse_cf_error"
    ERROR_CODE=$(echo $API_OUTPUT | jq -r '.errors[0].code')
    ERROR_MESSAGE=$(echo $API_OUTPUT | jq -r '.errors[0].message')
    _error "Error: $ERROR_CODE - $ERROR_MESSAGE"
}

# =====================================
# -- debug_json
# =====================================
cf_api_functions["_debug_jsons"]="Output JSON"
function _debug_json() {
    _debug "function:${FUNCNAME[0]} DEBUG_CURL_OUTPUT=$DEBUG_CURL_OUTPUT"
    if [[ $DEBUG_CURL_OUTPUT == "1" ]]; then
        _debug "******** Outputting JSON ********"
        _debug "${*}"
        _debug "******** Outputting JSON ********"
    else
        _debug "Not outputting JSON, use -DC"
    fi
}

# =====================================
# -- test_creds $ACCOUNT $API_KEY
# =====================================
cf_api_functions["test_creds"]="Test credentials"
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

# =====================================
# -- test_api_token $TOKEN
# =====================================
cf_api_functions["test_api_token"]="Test API Token"
function test-token () {
    _debug "function:${FUNCNAME[0]}"
    _running "Testing token via CLI"
    cf_api GET /client/v4/user/tokens/verify
    API_OUTPUT=$(echo $API_OUTPUT | jq '.messages[0].message' )
    [[ $CURL_EXIT_CODE == "200" ]] && _success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
}

# =============================================================================
# -- Cloudflare Zone Functions
# =============================================================================

# ===============================================
# -- _cf_zone_exists - check if zone exists
# --
# -- Arguments:	$1 - zone name
# ===============================================
cf_api_functions["_cf_zone_exists"]="Check if zone exists"
function _cf_zone_exists () {
	_debug "${*}"
	local ZONE="$1"
	
	ZONE_ID=$(_cf_zone_id "$ZONE")
	if [[ $? -ge 1 ]]; then
		_die "Zone does not exist - $ZONE"		
	else
		_success "Zone exists - $ZONE"		
	fi

}

# =====================================
# -- _cf_zone_id $DOMAIN_NAME
# -- Returns: message
# -- Get domain zoneid
# =====================================
cf_api_functions["_cf_zone_id"]="Get domain zoneid"
function _cf_zone_id () {
    DOMAIN_NAME=$1
    [[ -z $DOMAIN_NAME ]] && _error "Missing domain name" && exit 1
    _debug "function:${FUNCNAME[0]}"
    _debug "Getting zone_id for ${DOMAIN_NAME}"
    cf_api GET /client/v4/zones?name=${DOMAIN_NAME}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        ZONE_ID=$(echo $API_OUTPUT | jq -r '.result[0].id' )
        if [[ $ZONE_ID != "null" ]]; then
            _debug "Zone ID: $ZONE_ID"
            echo $ZONE_ID
        else
            _debug "Couldn't get ZoneID, using -z to provide ZoneID or give access read:zone access to your token"
            _debug "$MESG - $AP_OUTPUT"
            return 1
        fi
    else
        _debug "Couldn't get ZoneID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        _debug "$MESG - $AP_OUTPUT"
        return 1
    fi
}

# ===================================
# -- _cf_account_info $ACCOUNT_ID
# -- Get account id, account name and admins
# ===================================
cf_api_functions["_cf_account_info"]="Get account info"
function _cf_account_info () {
    local ACCOUNT_ID=$1
    local ACCOUNT_NAME=""
    _debug "function:${FUNCNAME[0]}"
    _debug "Getting account info for ${ACCOUNT_ID}"
    cf_api GET /client/v4/accounts/${ACCOUNT_ID}
    if [[ $CURL_EXIT_CODE == "200" ]]; then        
        ACCOUNT_NAME=$(echo $API_OUTPUT | jq -r '.result.name' )
        
        _debug "Account Name: $ACCOUNT_NAME - Account Email: $ACCOUNT_EMAIL"
        if [[ $ACCOUNT_NAME == "null" ]]; then
            _debug "Couldn't get AccountID, using -a to provide AccountID or give access read:account access to your token"
            _debug "$MESG - $AP_OUTPUT"
            exit 1
        fi
    else
        _debug "Couldn't get AccountID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        _debug "$MESG - $AP_OUTPUT"
        exit 1
    fi

    # -- Get admins on account
    cf_api GET /client/v4/accounts/${ACCOUNT_ID}/members
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        ACCOUNT_EMAIL="$(echo $API_OUTPUT | jq -r '.result[].user.email' )"
        _debug "Account Email: $ACCOUNT_EMAIL"
        if [[ $ACCOUNT_EMAIL != "null" ]]; then
            _debug "Account Email: $ACCOUNT_EMAIL"
        else
            _debug "Couldn't get AccountID, using -a to provide AccountID or give access read:account access to your token"
            _debug "$MESG - $AP_OUTPUT"
            exit 1
        fi
    else
        _debug "Couldn't get AccountID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        _debug "$MESG - $AP_OUTPUT"
        exit 1
    fi

    # -- Put array into one line.
    ACCOUNT_EMAIL_STRING="$(echo $ACCOUNT_EMAIL | tr '\n' ' ')"
    echo "ID: $ACCOUNT_ID Name: $ACCOUNT_NAME Members: ($ACCOUNT_EMAIL_STRING)"
}

# =====================================
# -- _cf_zone_create $ACCOUNT_ID $DOMAIN $SCAN
# -- Create zone under account
# =====================================
cf_api_functions["_cf_zone_create"]="Create zone under account"
function _cf_zone_create () {
    local ACCOUNT_ID=$1
    local DOMAIN=$2
    local SCAN=$3
    
    _debug "Creating zone $DOMAIN for tenant $ACCOUNT_ID with scan $SCAN"
    cf_api POST /client/v4/zones/ \
    -H "Content-Type: application/json" \
    -d '{
        "name": "'"$DOMAIN"'",
        "account": {
            "id": "'"$ACCOUNT_ID"'"            
        }
    }'
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        DOMAIN_ID=$(echo $API_OUTPUT | jq -r '.result.id')
        # -- Name Servers are in an array, separate by ;
        NAME_SERVERS=$(echo $API_OUTPUT | jq -r '.result.name_servers[]' | tr '\n' ';')
        _success "Zone $DOMAIN created with ID $DOMAIN_ID and Name Servers: $NAME_SERVERS"
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        return 1
    fi

    # -- Scan zone
    if [[ $SCAN == "true" ]]; then
        _cf_zone_scan $DOMAIN_ID
    else
        _warning "Skipping zone scan"
    fi    
    _quiet "$DOMAIN,$DOMAIN_ID,$NAME_SERVERS,$SCAN"
    return 0
}

# =====================================
# -- _cf_zone_scan $DOMAIN_ID
# =====================================
cf_api_functions["_cf_zone_scan"]="Scan zone"
function _cf_zone_scan () {
    local DOMAIN_ID=$1

    # -- Check if DOMAIN_ID is a domain or ID
    if [[ $DOMAIN_ID == *"."* ]]; then
        _debug "Getting zone ID for $DOMAIN_ID"
        DOMAIN_ID=$(_cf_zone_getid $DOMAIN_ID)
    fi
    
    cf_api POST /client/v4/zones/$DOMAIN_ID/dns_records/scan
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _success "Zone $DOMAIN_ID scanned"
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        return 1
    fi
}

# =====================================
# -- _cf_zone_create_bulk $FILE
# =====================================
cf_api_functions["_cf_zone_create_bulk"]="Create zone in bulk"
function _cf_zone_create_bulk () {
    _debug "Creating zones in bulk"
    local FILE=$1
    local TMP_FILE="/tmp/zones.tmp"
    local COUNT=0

    # -- Confirm
    _running2 "Creating zones in bulk"
    echo "===================================="
    echo "File: $FILE"
    cat $FILE
    echo "===================================="
    read -p "Are you sure you want to create zones in bulk? (y|n) " yn
    case $yn in
        [Yy]* )
        ;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
    # -- Ingest file account_id,domain,scan
    BULK_OUTPUT=""
    while IFS=, read -r DOMAIN ACCOUNT_ID SCAN; do
        # -- Check if line is blank
        if [[ -z $ACCOUNT_ID ]] || [[ -z $DOMAIN ]] || [[ -z $SCAN ]]; then
            _warning "Blank line found in file"
            continue
        fi
        _running "Creating zone $DOMAIN for account $ACCOUNT_ID with scan $SCAN"
        _debug "DOMAIN: $DOMAIN - ACCOUNT_ID: $ACCOUNT_ID - SCAN: $SCAN"
        QUIET="1"
        CREATE_DATA="$(_cf_zone_create $ACCOUNT_ID $DOMAIN $SCAN)"
        CREATE_DATA_EXIT="$?"
        QUIET="0"
        if [[ $CREATE_DATA_EXIT -ne 0 ]]; then
            _error "Error creating zone $DOMAIN"
            continue
        else
            BULK_OUTPUT+="$CREATE_DATA\n"
            COUNT=$((COUNT+1))
        fi
    done < $FILE
    _success "Created $COUNT zones"
    echo -e $BULK_OUTPUT
    echo -e $BULK_OUTPUT > $TMP_FILE
    _success "Output written to $TMP_FILE"
}



# =====================================
# -- _cf_zone_list $ACCOUNT_ID
# -- List all zones for current account or $ACCOUNT_ID
# =====================================
cf_api_functions["_cf_zone_list"]="List all zones"
function _cf_zone_list() {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local ZONE_QUERY="/client/v4/zones"
    local ACCOUNT_ID=$1
    [[ -n $ACCOUNT_ID ]] && ZONE_QUERY="/client/v4/zones/?account.id=$ACCOUNT_ID"

    _debug "Listing all zones"
    cf_api GET $ZONE_QUERY
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        ZONES=$(echo $API_OUTPUT | jq -r '.result[] | {id: .id, name: .name} | "\(.id) \(.name)"' | tr '\n' '\n')
        echo "$ZONES"
        if [[ $API_PAGES -gt 1 ]]; then
            _warning "More pages found $API_PAGES, use --all-pages to get all zones"
        else
            _success "All zones listed"
        fi
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- _cf_zone_get $ZONE_ID
# =====================================
cf_api_functions["_cf_zone_get"]="Get zone details"
function _cf_zone_get () {
    local ZONE_ID=$1
    local PRINT=$2
    
    [[ -z $PRINT ]] && PRINT="summary"
    if [[ $PRINT == "summary" ]]; then
        JQ_FILTER="jq '.result | {id: .id, name: .name, status: .status, type: .type, name_servers: .name_servers, account: .account.name, account_id: .account.id, created_on: .created_on, modified_on: .modified_on, tenant: .tenant, account: .account }'"
    elif [[ $PRINT == "export" ]]; then
        JQ_FILTER="jq -r '[.result | .name, .id, (.name_servers | join(\";\"))] | join(\",\")'"
    elif [[ $PRINT == "full" ]]; then
        JQ_FILTER="jq"
    else
        _error "Invalid print option"
        exit 1
    fi

    # -- Check if ZONE_ID is a domain or ID
    if [[ $ZONE_ID == *"."* ]]; then
        _debug "Getting zone ID for $ZONE_ID"
        ZONE_ID=$(_cf_zone_getid $ZONE_ID)
    fi

    _debug "Getting zone $ZONE_ID"
    cf_api GET /client/v4/zones/$ZONE_ID
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        echo $API_OUTPUT | eval "$JQ_FILTER"
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- _cf_zone_delete $ZONE_ID
# =====================================
cf_api_functions["_cf_zone_delete"]="Delete zone"
function _cf_zone_delete () {
    local ZONE_ID=$1
    _debug "Deleting zone $ZONE_ID"
    # -- Sure?
    read -p "Are you sure you want to delete zone $ZONE_ID? (y|n) " yn
    case $yn in
        [Yy]* )
        ;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac

    cf_api DELETE /client/v4/zones/$ZONE_ID
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _success "Zone $ZONE_ID deleted"
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- _cf_zone_count_records $ZONE_ID
# =====================================
cf_api_functions["_cf_zone_count_records"]="Count zone records"
function _cf_zone_count_records () {
    local ZONE_ID=$1

    # -- Check if zone is a domain or id
    if [[ $ZONE_ID == *"."* ]]; then
        _debug "Getting zone ID for $ZONE_ID"
        ZONE_ID=$(_cf_zone_getid $ZONE_ID)
    fi

    _debug "Counting records for zone $ZONE_ID"
    cf_api GET /client/v4/zones/$ZONE_ID/dns_records
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        RECORD_COUNT=$(echo $API_OUTPUT | jq -r '.result_info.count')
        _success "Total records: $RECORD_COUNT"
        _quiet "$RECORD_COUNT"
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- _cf_zone_records $ZONE_ID
# -- List all records for zone
# =====================================
cf_api_functions["_cf_zone_records"]="List all records"
function _cf_zone_records () {
    local ZONE_ID=$1
    _debug "Getting records for zone $ZONE_ID"
    
    # Get zone name for display purposes
    local ZONE_NAME=""
    cf_api GET /client/v4/zones/$ZONE_ID
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        ZONE_NAME=$(echo $API_OUTPUT | jq -r '.result.name')
        _debug "Zone name: $ZONE_NAME"
    else
        _error "Could not get zone name"
        ZONE_NAME="unknown"
    fi
    
    # Get DNS records
    cf_api GET /client/v4/zones/$ZONE_ID/dns_records

    if [[ $CURL_EXIT_CODE == "200" ]]; then
        # Create a temporary file for the data
        local tmp_file
        tmp_file=$(mktemp)
        
        # Output header to the temp file
        printf "%-32s %-40s %-10s %-60s %-10s %-10s\n" "ID" "Name" "Type" "Content" "TTL" "Proxied" > "$tmp_file"
        printf "%s\n" "$(printf '=%.0s' {1..160})" >> "$tmp_file"
        
        # Process each record with jq and output to temp file
        echo "$API_OUTPUT" | jq -r '.result[] | 
            [.id, .name, .type, .content, 
            (if .ttl == 1 then "Auto" else (.ttl|tostring) end), 
            (.proxied|tostring)] | 
            @tsv' | 
            while IFS=$'\t' read -r id name type content ttl proxied; do
                printf "%-32s %-40s %-10s %-60s %-10s %-10s\n" \
                    "$id" "$name" "$type" "$content" "$ttl" "$proxied" >> "$tmp_file"
            done
        
        # Display the formatted table
        cat "$tmp_file"
        rm "$tmp_file"
        
        # Show total count
        TOTAL_RECORDS=$(echo $API_OUTPUT | jq -r '.result_info.total_count')
        printf "\nTotal Records: %s\n" "$TOTAL_RECORDS"
        
        _success "Records listed for zone: $ZONE_NAME"
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- _cf_zone_count_records_bulk $FILE
# -- Count records in bulk
# =====================================
cf_api_functions["_cf_zone_count_records_bulk"]="Count records in bulk"
function _cf_zone_count_records_bulk () {
    local FILE=$1
    local TMP_FILE="/tmp/records.tmp"
    local COUNT=0

    # -- Confirm
    _running2 "Counting records in bulk"
    echo "===================================="
    echo "File: $FILE"
    cat $FILE
    echo "===================================="
    read -p "Are you sure you want to count records in bulk? (y|n) " yn
    case $yn in
        [Yy]* )
        ;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
    # -- Ingest file domain.com
    BULK_OUTPUT=""
    while IFS=, read -r DOMAIN; do
        # -- Check if line is blank
        if [[ -z $DOMAIN ]]; then
            _warning "Blank line found in file"
            continue
        fi
        _running "Counting records for zone $DOMAIN"
        _debug "DOMAIN: $DOMAIN"
        QUIET="1"
        RECORD_COUNT="$(_cf_zone_count_records $DOMAIN)"
        RECORD_COUNT_EXIT="$?"
        QUIET="0"
        if [[ $RECORD_COUNT_EXIT -ne 0 ]]; then
            _error "Error counting records for $DOMAIN"
            continue
        else
            BULK_OUTPUT+="$DOMAIN,$RECORD_COUNT\n"
            COUNT=$((COUNT+1))
        fi
    done < $FILE
    _success "Counted records for $COUNT zones"
    echo -e $BULK_OUTPUT
    echo -e $BULK_OUTPUT > $TMP_FILE
    _success "Output written to $TMP_FILE"
}


# =============================================================================
# -- Account Functions
# =============================================================================

# =====================================
# -- _get_account_id_from_creds
# -- Get account ID from credentials
# =====================================
cf_api_functions["_get_account_id_from_creds"]="Get account ID from credentials"
_get_account_id_from_creds () {
    _debug "function:${FUNCNAME[0]}"
    _debug "Getting account id from credentials"    
    cf_api GET /client/v4/user
    ACCOUNT_ID=$(echo $API_OUTPUT | jq -r '.result.id')
    if [[ $? -ne 0 ]]; then
        _debug "Return error from API: $CURL_EXIT_CODE - $API_OUTPUT"
        return 1
    elif [[ -z $ACCOUNT_ID ]]; then
        _debug "Account ID empty: $CURL_EXIT_CODE - $API_OUTPUT"
        return 1
    else
        echo $ACCOUNT_ID
    fi
}


# =====================================
# -- _cf_zone_accountid $DOMAIN
# =====================================
cf_api_functions["_cf_zone_accountid"]="Get account ID from zone"
_cf_zone_accountid() {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local DOMAIN_NAME=$1
    local ACCOUNTS_RETURNED=""
    local ACCOUNT_NAME=""

     cf_api GET /client/v4/zones?name=${DOMAIN_NAME}
    if [[ $CURL_EXIT_CODE != "200" ]]; then
        _error "Couldn't get account id, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        echo "$MESG - $AP_OUTPUT"
        exit 1
    fi
    
    # -- Get Account ID or ID's
    ACCOUNT_ID=$(echo $API_OUTPUT | jq -r '.result[].account.id' )
    _debug "Account ID: $ACCOUNT_ID"
    if [[ $ACCOUNT_ID == "null" ]]; then
        _error "No account id found for ${DOMAIN_NAME}"
        return 1
    else
        # -- Check if there are two accounts returned
        ACCOUNTS_RETURNED="$(echo "$ACCOUNT_ID" | wc -l)"
        _debug "Accounts Returned: $ACCOUNTS_RETURNED"
        if [[ $ACCOUNTS_RETURNED -gt 1 ]]; then
            _warning "Found multiple accounts for $DOMAIN_NAME, use -aid to specify account id"
            # -- List each account with a number, account id and account name
            i=1
            echo "$ACCOUNT_ID" | while read -r ACCOUNT; do
                ACCOUNT_ID=$(echo "$ACCOUNT" | awk '{print $1}')
                ACCOUNT_NAME="$(_cf_account_info $ACCOUNT_ID)"
                echo "$i - ID - $ACCOUNT_NAME"
                i=$((i+1))
            done
            return 1            
        fi
    fi
}

# =====================================
# -- _cf_get_account_id_from_zone $ZONE_ID
# =====================================
cf_api_functions["_cf_get_account_id_from_zone"]="Get account ID from zone"
function _cf_get_account_id_from_zone () {
    ZONE_ID=$1
    _debug "function:${FUNCNAME[0]}"
    _debug "Getting account_id for ${ZONE_ID}"
    cf_api GET /client/v4/zones/${ZONE_ID}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        ACCOUNT_ID=$(echo $API_OUTPUT | jq -r '.result.account.id' )
        _debug "Account ID: $ACCOUNT_ID"
        if [[ $ACCOUNT_ID != "null" ]]; then
            echo $ACCOUNT_ID
        else
            _debug "Couldn't get AccountID, using -a to provide AccountID or give access read:account access to your token"
            _debug "$MESG - $AP_OUTPUT"
            exit 1
        fi
    else
        _debug "Couldn't get AccountID, curl exited with $CURL_EXIT_CODE, check your \$CF_TOKEN or -t to provide a token"
        _debug "$MESG - $AP_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- get_permissions
# =====================================
cf_api_functions["get_permissions"]="Get permissions"
get_permissions () {
    _debug "Running get_permissions"
    cf_api GET /client/v4/user/tokens/permission_groups
}


# =============================================================================
# -- Cloudflare WAF Rule Functions
# =============================================================================

# ==================================
# -- cf_create_filter_json $ZONE_ID $JSON
# -- Create filter
# ==================================
cf_api_functions["cf_create_filter_json"]="Create WAF filter"
function cf_create_filter_json() {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local ZONE_ID=$1
    local JSON=$2
    _debug "Creating Filter - ZONE_ID: $ZONE_ID - JSON: $JSON"
    # -- Create JSON
    EXTRA=(-H "Content-Type: application/json" \
    -d "[$JSON]")

    if [[ $DRYRUN == "1" ]]; then
        _dryrun "URL = ${CF_API_ENDPOINT}"
        _dryrun "${EXTRA[@]}"
    else
        # -- Create filter via cf_api
        cf_api POST /client/v4/zones/${ZONE_ID}/filters "${EXTRA[@]}"
        if [[ $CURL_EXIT_CODE == "200" ]]; then
            NEW_FILTER_ID=$(echo $API_OUTPUT | jq -r '.result[].id')
            _debug "New Filter Created -- JSON: ${JSON} ID: ${NEW_FILTER}"
            echo $NEW_FILTER_ID
        else
            # -- Grabbing error message.
            CF_CREATE_FILTER_ERROR=$( echo "$API_OUTPUT" | jq -r '.errors[] | "\(.message)"')

            # -- Duplicate filter found
            if [[ $CF_CREATE_FILTER_ERROR == "config duplicates an already existing config" ]]; then
                CF_DUPLICATE_FILTER_ID=$( echo $CF_CREATE_FILTER_CURL | jq -r '.errors[] | "\(.meta.id)"')
                _error "Duplicate ID: $CF_DUPLICATE_FILTER_ID. Please delete this ID first."
                return 1
            else
                _error "$MESG - $API_OUTPUT"
                parse_cf_error "$API_OUTPUT"
                return 1
            fi
        fi
    fi
}


# ==================================
# -- CF_CREATE_FILTER $ZONE_ID $CF_EXPRESSION
# -- Create filter
# ==================================
cf_api_functions["CF_CREATE_FILTER"]="Create WAF filter"
function CF_CREATE_FILTER() {
	local ZONE_ID=$1
	local CF_EXPRESSION=$2
	_debug "Creating Filter - ZONE_ID: $ZONE_ID - CF_EXPRESSION: $CF_EXPRESSION"
	# -- Create JSON
	EXTRA=(-H "Content-Type: application/json" \
	-d '[
  {
    "expression": "'"$CF_EXPRESSION"'"
  }
  ]')


	if [[ $DRYRUN == "1" ]];then
		_dryrun " ** DRYRUN: URL = ${CF_API_ENDPOINT}"
		_dryrun " ** DRYRUN: expression = ${CF_EXPRESSION}"
	else
		# -- Create filter via cf_api
		cf_api POST /client/v4/zones/${ZONE_ID}/filters "${EXTRA[@]}"
		if [[ $CURL_EXIT_CODE == "200" ]]; then
			NEW_FILTER_ID=$(echo $API_OUTPUT | jq -r '.result[].id')
			_debug "New Filter Created -- Expression: ${CF_EXPRESSION} ID: ${NEW_FILTER}"
			echo $NEW_FILTER_ID
		else
			# -- Grabbing error message.
			CF_CREATE_FILTER_ERROR=$( echo "$API_OUTPUT" | jq -r '.errors[] | "\(.message)"')

			# -- Duplicate filter found
			if [[ $CF_CREATE_FILTER_ERROR == "config duplicates an already existing config" ]]; then
				CF_DUPLICATE_FILTER_ID=$( echo $CF_CREATE_FILTER_CURL | jq -r '.errors[] | "\(.meta.id)"')
            	_error "Duplicate ID: $CF_DUPLICATE_FILTER_ID. Please delete this ID first."
				return 1
			else
				_error "$MESG - $API_OUTPUT"
				parse_cf_error "$API_OUTPUT"
		        return 1
		    fi
	    fi
    fi
}


# ==================================
# -- CF_CREATE_RULE $ZONE_ID $FILTER_ID $ACTION $PRIORITY $DESCRIPTION
# -- Create rule
# ==================================
cf_api_functions["CF_CREATE_RULE"]="Create WAF rule"
function CF_CREATE_RULE () {
	local ZONE_ID=$1
	local FILTER_ID=$2
	local ACTION=$3
	local PRIORITY=$4
	local DESCRIPTION=$5

	_debug "Creating Rule - ZONE_ID: $ZONE_ID - FILTER_ID: $FILTER_ID - ACTION: $ACTION - PRIORITY: $PRIORITY - DESCRIPTION: $DESCRIPTION"
	# -- Create JSON
	EXTRA=(-H "Content-Type: application/json" \
	-d '[
  {
    "filter": {
      "id": "'"${FILTER_ID}"'"
    },
    "action": "'"${ACTION}"'",
    "priority": '"${PRIORITY}"',
    "description": "'"${DESCRIPTION}"'"
  }
]')


    if [[ $DRYRUN == "1" ]]; then
        _dryrun "URL = ${CF_API_ENDPOINT}"
		_dryrun "${EXTRA[@]}"
    else
		# -- Create filter via cf_api
		cf_api POST /client/v4/zones/${ZONE_ID}/firewall/rules "${EXTRA[@]}"
		if [[ $CURL_EXIT_CODE == "200" ]]; then
			CF_CREATE_RULE_RESULT=$( echo $API_OUTPUT | jq -r '.success')
			NEW_RULE=$(echo $API_OUTPUT | jq '.result[].value')
			_debug "New Rule -- ${DESCRIPTION}: ${NEW_RULE}"
			echo $NEW_RULE
		else
			_error "ERROR: $MESG - $API_OUTPUT"
			exit 1
		fi
	fi
}

# =====================================
# -- cf_list_rules_action $DOMAIN $ZONE_ID
# =====================================
cf_api_functions["cf_list_rules_action"]="List all rules"
function cf_list_rules_action () {
    local DOMAIN_NAME=$1 ZONE_ID=$2
    _debug "function:${FUNCNAME[0]}"
    _running "Listing all rules for ${DOMAIN}/${ZONE_ID}"
    cf_api GET /client/v4/zones/${ZONE_ID}/firewall/rules
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _success "Success from API: $CURL_EXIT_CODE"
        # -- Get Total Rules
        TOTAL_RULES=$(echo $API_OUTPUT | jq -r '.result_info.total_count')
        if [[ $TOTAL_RULES == "0" ]]; then
            _warning "No rules found for ${DOMAIN}/${ZONE_ID}"
        else
            _success "Found Rules for ${DOMAIN}/${ZONE_ID} - Total Rules: $TOTAL_RULES"
            echo
            # -- Go through each rule and print out in numbered order
            echo $API_OUTPUT | jq -r '.result[] | "\(.id) \(.description)"' | awk '{print "#" NR, $0}'

        fi
    else
        _error "Error from API: $CURL_EXIT_CODE"
        parse_cf_error "$API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- cf_list_rules $ZONE_ID
# -- Get Rules
# =====================================
cf_api_functions["cf_list_rules"]="List all rules"
function cf_list_rules() {
    local ZONE_ID=$1
    _debug "Getting rules on $ZONE_ID"
    cf_api GET /client/v4/zones/${ZONE_ID}/firewall/rules
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        echo $API_OUTPUT
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- cf_get_rule $ZONE_ID $RULE_ID
# -- Get Rule
# =====================================
cf_api_functions["cf_get_rule"]="Get rule"
function cf_get_rule() {
    local ZONE_ID=$1
    local RULE_ID=$2
    _debug "Getting rule $RULE_ID on $ZONE_ID"
    cf_api GET /client/v4/zones/${ZONE_ID}/firewall/rules/${RULE_ID}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        # Print out each item and separate with an
        echo $API_OUTPUT
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- cf_delete_rules_action $DOMAIN_NAME $ZONE_ID
# -- Delete all rules
# =====================================
cf_api_functions["cf_delete_rules_action"]="Delete all rules"
function cf_delete_rules_action () {
	DOMAIN_NAME=$1
    ZONE_ID=$2
    OBJECT="${DOMAIN_NAME}/${ZONE_ID}"
	_running2 "Deleting all rules on ${OBJECT}"
	
    # -- Get a list of all rules
	ZONE_RULES=$(cf_list_rules $ZONE_ID)

	# -- Loop through all rules and delete
	ZONE_RULES_COUNT=$(echo $ZONE_RULES | jq -r '.result_info.count')
	if [[ $ZONE_RULES_COUNT == "0" ]]; then
		_error "No rules found for ${OBJECT}"
		exit 1
	else
		# -- Print out rules
		_running2 "Looping rules $ZONE_RULES_COUNT on ${OBJECT} to delete"
		echo ""
		echo "$ZONE_RULES" | jq -r '.result[] | "\(.id) \(.description)"' | awk '{print "#" NR, $0}'
		echo ""
        
        # -- Ask user if they want to delete all rules at once
        read -p "Do you want to delete all rules at once? (y|n) " delete_all
        if [[ $delete_all == [Yy]* ]]; then
            for RULE_ID in $(echo $ZONE_RULES | jq -r '.result[].id'); do
                cf_delete_rule $ZONE_ID $RULE_ID
                FILTER_ID=$(echo $ZONE_RULES | jq -r --arg RULE_ID "$RULE_ID" '.result[] | select(.id == $RULE_ID) | .filter.id')
                cf_delete_filter $ZONE_ID $FILTER_ID
            done
            _success "All rules deleted."
		else
            # -- Loop through all rules
            _debug "Looping through rules to get filter ID's"
            for RULE_ID in $(echo $ZONE_RULES | jq -r '.result[].id'); do
                _debug "Rule ID: $RULE_ID"
                RULE_OUTPUT=$(cf_get_rule $ZONE_ID $RULE_ID | jq -r '.result | [.id, .description, .filter.id] | join("|")')
                _debug "Rule Output: $RULE_OUTPUT"
                # Get Rule Data, each on new line
                while IFS='|' read -r RULE_ID2 DESCRIPTION FILTER_ID; do
                    _debug "Rule ID: $RULE_ID2 - Description: $DESCRIPTION - Filter ID: $FILTER_ID"
                    FILTER_ID_DELETE=$FILTER_ID
                    FILTER_DESCRIPTION=$DESCRIPTION
                done <<< "$RULE_OUTPUT"
                _running3 "Rule: $RULE_ID Filter: $FILTER_ID_DELETE Description: $FILTER_DESCRIPTION"
                read -p "  - Delete rule? $RULE_ID (y|n)" yn
                case $yn in
                    [Yy]* )
                    cf_delete_rule $ZONE_ID $RULE_ID
                    cf_delete_filter $ZONE_ID $FILTER_ID_DELETE
                    echo
                    ;;
                    [Nn]* ) exit;;
                    * ) echo "Please answer yes or no.";;
                esac
            done
        fi
	fi
}

# =====================================
# -- cf_delete_rule_action $DOMAIN_NAME $ZONE_ID $RULE_ID
# -- Delete rule
# =====================================
cf_api_functions["cf_delete_rule_action"]="Delete rule"
function cf_delete_rule_action () {
	local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local RULE_ID=$3
    OBJECT="${DOMAIN_NAME}/${ZONE_ID}"

    # -- Check if rule exists
    RULE_EXISTS=$(cf_get_rule $ZONE_ID $RULE_ID)
    if [[ $? -ne 0 ]]; then
        _error "Rule $RULE_ID doesn't exist on $OBJECT"
        return 1
    else
        # -- Get Rule Data, print and set variables
        while IFS='|' read -r RULE_ID2 DESCRIPTION FILTER_ID; do
            _debug "Rule ID: $RULE_ID2 - Description: $DESCRIPTION - Filter ID: $FILTER_ID"
            FILTER_ID_DELETE=$FILTER_ID
            FILTER_DESCRIPTION=$DESCRIPTION
        done <<< "$RULE_EXISTS"
        _running2 "Rule: $RULE_ID Filter: $FILTER_ID_DELETE Description: $FILTER_DESCRIPTION"
        read -p "  - Delete rule? (y|n)" yn
        case $yn in
            [Yy]* )
            cf_delete_rule $ZONE_ID $RULE_ID
            CF_DELETE_FILTER $ZONE_ID $FILTER_ID_DELETE
            ;;
            [Nn]* ) exit;;
            * ) echo "Please answer yes or no.";;
        esac
    fi
}

# =====================================
# -- cf_delete_rule $ZONE_ID $RULE_ID
# -- Delete rule
# =====================================
cf_api_functions["cf_delete_rule"]="Delete rule"
function cf_delete_rule () {
    local ZONE_ID=$1
    local RULE_ID=$2
    OBJECT="${DOMAIN_NAME}/${ZONE_ID}"

	_debug "Deleting rule $RULE_ID on $OBJECT"

	cf_api DELETE /client/v4/zones/${ZONE_ID}/firewall/rules/${RULE_ID}

    if [[ $CURL_EXIT_CODE == "200" ]]; then
		_success "Rule $RULE_ID deleted"
	else
		_error "ERROR: $MESG - $API_OUTPUT"
		exit 1
	fi
}

# ==================================
# cf_list_filters_action $DOMAIN $ZONE_ID
# -- Get Filters
# ==================================
cf_api_functions["cf_list_filters_action"]="List all filters"
function cf_list_filters_action () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2

    OBJECT="${DOMAIN_NAME}/${ZONE_ID}"
    _running2 "Listing all filters for ${OBJECT}"

    cf_api GET /client/v4/zones/${ZONE_ID}/filters
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _success "Success from API: $CURL_EXIT_CODE"
        # -- Get Total Filters
        TOTAL_FILTERS=$(echo $API_OUTPUT | jq -r '.result_info.total_count')
        if [[ $TOTAL_FILTERS == "0" ]]; then
            _warning "No filters found for ${DOMAIN_NAME}/${ZONE_ID}"
        else
            _success "Found Filters for ${DOMAIN_NAME}/${ZONE_ID} - Total Filters: $TOTAL_FILTERS"
            echo
            # -- Go through each filter and print out in numbered order
        echo $API_OUTPUT | jq -r '.result[] | "\(.id) \(.expression) \(.paused)"' | \
        awk '{print "#" NR, $0"\n----------------------------------------"}'
        fi
    else
        _error "Error from API: $CURL_EXIT_CODE"
        parse_cf_error "$API_OUTPUT"
        exit 1
    fi
}

# =====================================
# cf_list_filters $ZONE_ID
# -- Get Filters
# ==================================
cf_api_functions["cf_list_filters"]="List all filters"
function CF_GET_FILTERS() {
	local ZONE_ID=$1
	_debug "Getting filters on $ZONE_ID"
	cf_api GET /client/v4/zones/${ZONE_ID}/filters
	if [[ $CURL_EXIT_CODE == "200" ]]; then
		echo $API_OUTPUT
	else
		_error "ERROR: $MESG - $API_OUTPUT"
		exit 1
	fi
}

# =====================================
# -- cf_list_filter $ZONE_ID $FILTER_ID
# -- Get Filter
# =====================================
cf_api_functions["cf_list_filter"]="List filter"
function cf_list_filter () {
    local ZONE_ID=$1
    local FILTER_ID=$2
    _debug "Getting filter $FILTER_ID on $ZONE_ID"
    cf_api GET /client/v4/zones/${ZONE_ID}/filters/${FILTER_ID}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        echo $API_OUTPUT
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- cf_delete_filter_action $DOMAIN_NAME $ZONE_ID $FILTER_ID
# -- Delete filter
# =====================================
cf_api_functions["cf_delete_filter_action"]="Delete filter"
function cf_delete_filter_action () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2
    local FILTER_ID=$3
    OBJECT="${DOMAIN_NAME}/${ZONE_ID}"
    _running2 "Deleting filter $FILTER_ID on $OBJECT"
    cf_delete_filter $ZONE_ID $FILTER_ID
    if [[ $? -eq 0 ]]; then
        _success "Filter $FILTER_ID deleted"
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- cf_delete_filters_action $DOMAIN_NAME $ZONE_ID
# -- Delete all filters
# =====================================
cf_api_functions["cf_delete_filters_action"]="Delete all filters"
function cf_delete_filters_action () {
    local DOMAIN_NAME=$1
    local ZONE_ID=$2

    OBJECT="${DOMAIN_NAME}/${ZONE_ID}"
    _running2 "Deleting all filters on $OBJECT"

    # -- Get a list of all filters
    ZONE_FILTERS=$(CF_GET_FILTERS $ZONE_ID)

    # -- Loop through all filters and delete
    ZONE_FILTERS_COUNT=$(echo $ZONE_FILTERS | jq -r '.result_info.count')
    if [[ $ZONE_FILTERS_COUNT == "0" ]]; then
        _error "No filters found for $OBJECT"
        exit 1
    else
        # -- Print out filters
        _running2 "Looping filters $ZONE_FILTERS_COUNT on $OBJECT to delete"
        echo ""
        echo "$ZONE_FILTERS" | jq -r '.result[] | "\(.id) \(.expression) \(.paused)"' | \
        awk '{print "#" NR, $0"\n----------------------------------------"}'
        echo ""
        # -- Loop through all filters
        _debug "Looping through filters to get filter ID's"
        for FILTER_ID in $(echo $ZONE_FILTERS | jq -r '.result[] | "\(.id)"'); do
            # -- Print out filter seperate by |
            FILTER_OUTPUT=$(cf_list_filter $ZONE_ID $FILTER_ID | jq -r '.result | [.id, .expression, .paused] | join("|")')
            # Get Filter Data, print and set variables
            while IFS='|' read -r FILTER_ID2 EXPRESSION PAUSED; do
                _debug "Filter ID: $FILTER_ID2 - Expression: $EXPRESSION - Paused: $PAUSED"
                FILTER_ID_DELETE=$FILTER_ID2
                FILTER_EXPRESSION=$EXPRESSION
                FILTER_PAUSED=$PAUSED
            done <<< "$FILTER_OUTPUT"
            _running3 "Filter: $FILTER_ID_DELETE Expression: $FILTER_EXPRESSION Paused: $FILTER_PAUSED"
            read -p " - Delete filter $FILTER_ID_DELETE? (y|n)" yn
            case $yn in
                [Yy]* )
                DELETE_OUTPUT=$(cf_delete_filter $ZONE_ID $FILTER_ID_DELETE)
                [[ $? -eq 0 ]] && _success "Filter $FILTER_ID_DELETE deleted"
                ;;
                [Nn]* ) exit;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    fi
}

# =====================================
# -- cf_delete_filter $ZONE_ID $FILTER_ID
# -- Delete filter
# =====================================
cf_api_functions["cf_delete_filter"]="Delete filter"
function cf_delete_filter () {
	local ZONE_ID=$1
	local FILTER_ID=$2

	_debug "Deleting filter $FILTER_ID on zone $ZONE_ID"

	cf_api DELETE /client/v4/zones/${ZONE_ID}/filters/${FILTER_ID}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
		_success "Filter $RULE_ID deleted"
	else
		_error "ERROR: $MESG - $API_OUTPUT"
		exit 1
	fi
}

# =============================================================================
# -- Cloudflare WAF Rulesets
# =============================================================================

# =====================================
# -- cf_list_rulesets $ZONE_ID
# -- List all rulesets
# =====================================
cf_api_functions["cf_list_rulesets"]="List all rulesets"
function cf_list_rulesets () {
    local ZONE_ID=$1
    _debug "Getting rulesets on $ZONE_ID"
    cf_api GET /client/v4/zones/${ZONE_ID}/rulesets
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        echo $API_OUTPUT | jq -r
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- cf_get_ruleset $ZONE_ID $RULESET_ID
# -- Get ruleset
# =====================================
cf_api_functions["cf_get_ruleset"]="Get ruleset"
function cf_get_ruleset () {
    local ZONE_ID=$1
    local RULESET_ID=$2
    _debug "Getting ruleset $RULESET_ID on $ZONE_ID"
    cf_api GET /client/v4/zones/${ZONE_ID}/rulesets/${RULESET_ID}
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        echo $API_OUTPUT | jq -r
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- cf_get_ruleset_fw_custom_id $ZONE_ID
# -- Get ruleset http_request_firewall_custom ID
# =====================================
cf_api_functions["cf_get_ruleset_fw_custom_id"]="Get ruleset http_request_firewall_custom ID"
function cf_get_ruleset_fw_custom_id () {
    local ZONE_ID=$1
    local PHASE="http_request_firewall_custom"
    
    _debug "Getting ruleset $PHASE on $ZONE_ID"
    cf_api GET /client/v4/zones/${ZONE_ID}/rulesets
    [[ $CURL_EXIT_CODE -ne 200 ]] && _error "Couldn't get data from ruleset endpoint" && exit 1
    FIREWALL_CUSTOM=$(echo $API_OUTPUT | jq -r --arg PHASE "$PHASE" '.result[] | select(.phase == $PHASE) | .id')
    [[ -z $FIREWALL_CUSTOM ]] && _error "Couldn't get ruleset for $PHASE" && exit 1
    _debug "Ruleset ID: $FIREWALL_CUSTOM"
    echo "$FIREWALL_CUSTOM"
}

# =====================================
# -- cf_get_ruleset_fw_custom $ZONE_ID
# -- Get ruleset http_request_firewall_custom
# =====================================
cf_api_functions["cf_get_ruleset_fw_custom"]="Get ruleset http_request_firewall_custom"
function cf_get_ruleset_fw_custom () {
    local ZONE_ID=$1    
    
    _debug "Getting ruleset $PHASE on $ZONE_ID"
    FIREWALL_CUSTOM=$(cf_get_ruleset_fw_custom_id $ZONE_ID)
    [[ -z $FIREWALL_CUSTOM ]] && _error "Couldn't get ruleset for $PHASE" && exit 1
    _debug "Ruleset ID: $FIREWALL_CUSTOM"
    # -- Get Ruleset Data
    cf_get_ruleset $ZONE_ID $FIREWALL_CUSTOM
    [[ $CURL_EXIT_CODE -ne 200 ]] && _error "Couldn't get data from ruleset endpoint" && exit 1    
}

# =============================================================================
# -- Cloudflare Tenant Commands
# =============================================================================

# ===============================================
# -- _cf_tenant_create $TENANT_NAME $ACCOUNT_ID
# -- Create a tenant
# ===============================================
cf_api_functions["_cf_tenant_create"]="Create a tenant"
function _cf_tenant_create () {
	_debug "function:${FUNCNAME[0]} - ${*}"
	local TENANT_NAME="$1" ACCOUNT_ID="$2"

	# -- Create Tenant
	_debug "Creating tenant - $TENANT_NAME"
    EXTRA=(-H "Content-Type: application/json" \
    -d '{
        "name": "'"${TENANT_NAME}"'"
    }')

	cf_api POST /client/v4/accounts "${EXTRA[@]}"
    
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        NEW_TENANT_ID=$(echo $API_OUTPUT | jq -r '.result.id')
        _debug "New Tenant Created -- Name: ${TENANT_NAME} ID: ${NEW_TENANT_ID}"
        _success "Created Tenant: $NEW_TENANT_ID"
        _quiet "$NEW_TENANT_ID"
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi

    _running2 "Getting tenant $NEW_TENANT_ID"
    CONFIRM_TENANT="$(_cf_tenant_get $NEW_TENANT_ID)"
    [[ $? -ne 0 ]] && _error "Couldn't get tenant" && exit 1
    _success "Tenant: $CONFIRM_TENANT"

}

# ===============================================
# -- _cf_tenant_create_bulk $FILE
# -- Create a tenant
# ===============================================
cf_api_functions["_cf_tenant_create_bulk"]="Create a tenant"
function _cf_tenant_create_bulk () {
    _debug "function:${FUNCNAME[0]} - ${*}"
	local FILE="$1"
    local COUNT=0
    local TMP_FILE="/tmp/tenants.tmp"
    local TENANT_IDS_CREATED

    # -- Print out all tenants about to be created
    _running2 "Creating tenants from file: $FILE"
    echo "===================================="
    cat $FILE
    echo "===================================="

    # -- Confirm?
    read -p "Do you want to continue? (y|n) " yn
    case $yn in
        [Yy]* )
        _running2 "Creating tenants"
        ;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
    echo "Continuing..."

    # -- Each line is a company name
    QUIET="1"
    while IFS= read -r LINE; do
        _debug "Creating tenant - $LINE"        
        TENANT_ID="$(_cf_tenant_create "$LINE")"
        echo "\"$LINE\",$TENANT_ID"
        TENANT_IDS_CREATED+="\"$LINE\",$TENANT_ID\n"
        COUNT=$((COUNT+1))
        sleep 1
    done < $FILE
    # shellcheck disable=SC2034
    QUIET="0"

    _running2 "Created $COUNT tenants"
    # -- Print out all tenants created into a file
    echo -e $TENANT_IDS_CREATED > $TMP_FILE
    _success "Tenants created: $TMP_FILE"
}

# ===============================================
# -- _cf_tenant_get $TENANT_ID
# -- List a tenant
# ===============================================
cf_api_functions["_cf_tenant_get"]="Get a tenant"
function _cf_tenant_get () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local TENANT_ID="$1"
    [[ -z $TENANT_ID ]] && _error "Missing tenant ID" && exit 1

    # -- List Tenant
    _debug "Listing tenant"
    cf_api GET /client/v4/accounts/$TENANT_ID
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        echo $API_OUTPUT | jq -r '.result | "\(.id) \(.name)"'
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# ===============================================
# -- _cf_tenant_list_all $ACCOUNT_ID
# -- List all tenants
# ===============================================
cf_api_functions["_cf_tenant_list_all"]="List all tenants"
function _cf_tenant_list_all () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local ACCOUNT_ID="$1"

    # -- List Tenants
    _debug "Listing tenants for $ACCOUNT_ID"
    cf_api GET /client/v4/accounts
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        echo $API_OUTPUT | jq -r '.result[] | "\(.id) \(.name)"' | awk '{print "#" NR, $0}'        
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# ===============================================
# -- _cf_tenant_delete $TENANT_ID
# -- Delete a tenant
# ===============================================
cf_api_functions["_cf_tenant_delete"]="Delete a tenant"
function _cf_tenant_delete () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local TENANT_ID="$1"
    [[ -z $TENANT_ID ]] && _error "Missing tenant ID" && exit 1

    # -- Delete Tenant
    _debug "Deleting tenant"
    
    cf_api DELETE /client/v4/accounts/$TENANT_ID
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _success "Deleted Tenant: $TENANT_ID"
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# ===============================================
# -- _cf_tenant_delete_bulk $TENANT_IDS
# -- Delete multiple tenants
# ===============================================
cf_api_functions["_cf_tenant_delete_bulk"]="Delete multiple tenants"
function _cf_tenant_delete_bulk () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local TENANT_IDS="${*}"
    [[ -z $TENANT_IDS ]] && _error "Missing tenant IDs" && exit 1

    # -- Break up tenants separated by , and put into array
    IFS=',' read -r -a TENANT_IDS <<< "$TENANT_IDS"
    for TENANT_ID in "${TENANT_IDS[@]}"; do
        _cf_tenant_delete $TENANT_ID
    done
}

# ===============================================
# -- _cf_tenant_roles_get $TENANT_ID
# -- Get tenant roles
# ===============================================
cf_api_functions["_cf_tenant_roles_get"]="Get tenant roles"
function _cf_tenant_roles_get () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local TENANT_ID="$1"
    [[ -z $TENANT_ID ]] && _error "Missing tenant ID" && exit 1

    # -- Get Tenant Roles
    _debug "Getting tenant roles"
    cf_api GET /client/v4/accounts/$TENANT_ID/roles
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        echo $API_OUTPUT | jq -r '.result[] | "\(.id) \(.name)"' | awk '{print "#" NR, $0}'
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# ===============================================
# -- _cf_tenant_access_add $TENANT_ID $EMAIL $ROLE
# -- Create a tenant access
# ===============================================
cf_api_functions["_cf_tenant_access_add"]="Create a tenant access"
function _cf_tenant_access_add () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local TENANT_ID="$1" EMAIL="$2" ROLE="$3"
    [[ -z $TENANT_ID ]] && _error "Missing tenant ID" && exit 1
    [[ -z $EMAIL ]] && _error "Missing email" && exit 1
    [[ -z $ROLE ]] && _error "Missing role" && exit 1

    # -- Role Mapping
    # 05784afa30c1afe1440e79d9351c7430 - Administrator

    if [[ $ROLE == "administrator" ]]; then
        ROLE_ID="05784afa30c1afe1440e79d9351c7430"
    else
        _error "Invalid role"
        exit 1
    fi

    # -- Create Tenant Access
    _debug "Creating tenant access - $EMAIL - $ROLE_ID"
    EXTRA=(-H "Content-Type: application/json" \
    -d '{
        "email": "'"${EMAIL}"'",
        "roles": ["'"${ROLE_ID}"'"]
    }')

    cf_api POST /client/v4/accounts/$TENANT_ID/members "${EXTRA[@]}"
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _success "New Tenant Access Created"
        echo $API_OUTPUT | jq -r '.result | "ID: \(.user.id) First Name: \(.user.first_name) Last Name: \(.user.last_name) Email: \(.user.email) 2FA: \(.two_factor_authentication_enabled) Status: \(.status)"'
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# ===============================================
# -- _cf_tenant_access_get $TENANT_ID
# -- Get a tenant access
# ===============================================
cf_api_functions["_cf_tenant_access_get"]="Get a tenant access"
function _cf_tenant_access_get () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local $TENANT_ID="$1"
    [[ -z $TENANT_ID ]] && _error "Missing tenant access ID" && exit 1

    # -- Get Tenant Access
    _debug "Getting tenant access"
    cf_api GET /client/v4/accounts/${TENANT_ID}/members
    if [[ $CURL_EXIT_CODE == "200" ]]; then      
        # -- Figure out how many members
        TOTAL_MEMBERS=$(echo $API_OUTPUT | jq -r '.result_info.total_count')
        if [[ $TOTAL_MEMBERS == "0" ]]; then
            _warning "No members found for $TENANT_ID"
        else
            _success "Found Members for $TENANT_ID - Total Members: $TOTAL_MEMBERS"
            echo
            # -- Go through each member and print out in numbered order
            # -- Get a list of ID's into an array
            MEMBER_IDS=($(echo $API_OUTPUT | jq -r '.result[] | "\(.id)"'))
            # -- Loop through each member and get the details
            for MEMBER_ID in "${MEMBER_IDS[@]}"; do                
                # -- Get the member details via jq
                MEMBER=$(echo $API_OUTPUT | jq -r --arg MEMBER_ID "$MEMBER_ID" '.result[] | select(.id == $MEMBER_ID)')
                _debug "member: $MEMBER"
                echo "Member ID: $MEMBER_ID"
                echo "----------------------------------------"
                # -- Output the member details each item on a new line
                echo $MEMBER | jq -r '"ID: \( .id )\nID2: \(.user.id) \nEmail: \(.user.email) \n2FA: \(.two_factor_authentication_enabled) \nStatus: \(.status) \nRole: \(.roles[].name)"'
                #echo $MEMBER #| jq -r '"STATUS\tROLE" + "\t" + .status + "\t" + .role' | column -t -s $'\t'
                echo
            done
        fi
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# ===============================================
# -- _cf_tenant_access_get_member $TENANT_ID $MEMBER_ID
# -- Get a tenant access
# ===============================================
cf_api_functions["_cf_tenant_access_get_member"]="Get a tenant access"
function _cf_tenant_access_get_member () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local $TENANT_ID="$1" MEMBER_ID="$2"
    [[ -z $TENANT_ID ]] && _error "Missing tenant ID" && exit 1
    [[ -z $MEMBER_ID ]] && _error "Missing member ID" && exit 1

    # -- Get Tenant Access
    _debug "Getting tenant access"
    cf_api GET /client/v4/accounts/${TENANT_ID}/members/$MEMBER_ID
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _running2 "Member ID: $MEMBER_ID"
        echo "========================================"
        echo $API_OUTPUT | jq -r '.result | "ID: \(.user.id)\n First Name: \(.user.first_name)\n Last Name: \(.user.last_name)\n Email: \(.user.email)\n 2FA: \(.two_factor_authentication_enabled)\n Status: \(.status)"'
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# ===============================================
# -- _cf_tenant_access_delete $TENANT_ID $MEMBER_ID
# -- Delete a tenant access
# ===============================================
cf_api_functions["_cf_tenant_access_delete"]="Delete a tenant access"
function _cf_tenant_access_delete () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local TENANT_ID="$1" MEMBER_ID="$2"
    [[ -z $TENANT_ID ]] && _error "Missing tenant ID" && exit 1
    [[ -z $MEMBER_ID ]] && _error "Missing member ID" && exit 1

    # -- Delete Tenant Access
    _debug "Deleting tenant access"
    cf_api DELETE /client/v4/accounts/$TENANT_ID/members/$MEMBER_ID
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        _success "Deleted Tenant Access: $MEMBER_ID"
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit 1
    fi
}

# =====================================
# -- _cf_get_member_id_from_email $TENANT_ID $EMAIL 
# -- Get member ID from email
# =====================================
cf_api_functions["_cf_get_member_id_from_email"]="Get member ID from email"
function _cf_get_member_id_from_email () {
    _debug "function:${FUNCNAME[0]} - ${*}"
    local TENANT_ID="$1" EMAIL="$2"
    [[ -z $TENANT_ID ]] && _error "Missing tenant ID" && exit 1
    [[ -z $EMAIL ]] && _error "Missing email" && exit 1

    # -- Get Tenant Access
    _debug "Getting tenant access"
    cf_api GET /client/v4/accounts/${TENANT_ID}/members
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        # -- Get member ID from email
        MEMBER_ID=$(echo $API_OUTPUT | jq -r --arg EMAIL "$EMAIL" '.result[] | select(.user.email == $EMAIL) | .id')
        if [[ -z $MEMBER_ID ]]; then
            _error "No member found for $EMAIL"
            exit 1
        else
            echo $MEMBER_ID
        fi
    else
        _error "ERROR: $MESG - $API_OUTPUT"
        exit
    fi
}




# ==================================================================================
# -- Cloudflare Turnstile Functions
# ==================================================================================
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
    _debug "function:${FUNCNAME[0]} - ${*}"
    local DOMAIN_NAME=$1
    local ACCOUNT_ID=$2
    local TURNSTILE_NAME=$3
    local EXTRA=()

    EXTRA=(-H "Content-Type: application/json" \
     --data 
    '{
        "domains": [
            "'$DOMAIN_NAME'"
        ],
        "mode": "non-interactive",
        "name": "'$TURNSTILE_NAME'",
        "clearance_level": "no_clearance"
        }')
    
    # -- Create Turnstile
    cf_api POST /client/v4/accounts/${ACCOUNT_ID}/challenges/widgets "${EXTRA[@]}"
    
    if [[ $CURL_EXIT_CODE == "200" ]]; then
        json2_keyval $API_OUTPUT        
    else        
        echo "$MESG - $API_OUTPUT"
        exit 1
    fi
}

# ==================================
# -- _cf_list_turnstile $ACCOUNT_ID
# -- List all turnstile tokens
# ==================================
function _cf_list_turnstile () {
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

# ===================================================================================
# -- Cloudflare Settings Functions
# ===================================================================================

# =====================================
# -- Cloudflare Settings Variables
# =====================================

declare -a CF_SETTINGS

# Add settings to the array
CF_SETTINGS["security_level"]="Security Level"
CF_SETTINGS["challenge_ttl"]="Challenge TTL"
CF_SETTINGS["browser_check"]="Browser Check"
CF_SETTINGS["always_use_https"]="Always Use HTTPS"
CF_SETTINGS["min_tls_version"]="Minimum TLS Version"

CF_SETTINGS_ALLOWED=("security_level" "challenge_ttl" "browser_check" "always_use_https")
# -- Challenge TTL
# Defaults for challenge ttl -
CF_DEFAULTS_CHALLENGE_TTL=(300 900 1800 2700 3600 7200 10800 14400 28800 57600 86400 604800 2592000 31536000)
CF_DEFAULTS_SECURITY_LEVEL=("essentially_off" "low" "medium" "high" "under_attack")
CF_DEFAULTS_BROWSER_CHECK=("on" "off")
CF_DEFAULTS_ALWAYS_USE_HTTPS=("on" "off")
CF_DEFAULTS_MIN_TLS_VERSION=("1.0" "1.1" "1.2" "1.3")

# ==========================================
# -- usage_set_settings
# ===========================================
function usage_set_settings () {
	echo "Usage: $SCRIPT_NAME set-settings <domain> <setting> <value>"
	echo ""
	echo " Settings"
	# -- Loop through CF_SETTINGS array and print out key
	for i in "${!CF_SETTINGS[@]}"; do
		echo "   ${i}"
	done
	echo ""
}

# ==================================================
# -- _convert_seconds $SECONDS
# -- returns $HUMAN_TIME
# ==================================================
function _convert_seconds () {
    local T=$1
    local D=$((T/60/60/24))
    local H=$((T/60/60%24))
    local M=$((T/60%60))
    local S=$((T%60))
    local HUMAN_TIME

    if [ "$D" -gt 0 ]; then
        HUMAN_TIME="${D}d ${H}h ${M}m ${S}s"
    elif [ "$H" -gt 0 ]; then
        HUMAN_TIME="${H}h ${M}m ${S}s"
    elif [ "$M" -gt 0 ]; then
        HUMAN_TIME="${M}m ${S}s"
    else
        HUMAN_TIME="${S}s"
    fi

    echo "$HUMAN_TIME"
}

# ==================================================
# -- _cf_get_settings $CF_ZONEID
# ==================================================
function _cf_get_settings () {	
    _debug "function:${FUNCNAME[0]} - ${*}"
    local CF_ZONE_ID=$1    

    # -- Get Zone Settings
    cf_api "GET" "/client/v4/zones/${CF_ZONE_ID}/settings"
    _debug "API_OUTPUT: $API_OUTPUT CURL_EXIT_CODE: $CURL_EXIT_CODE"

    # -- Process each setting we're interested in
    for SETTING in "${!CF_SETTINGS[@]}"; do
        _debug "Processing setting: $SETTING"
        # Extract the value for this specific setting ID from the results array
        SETTING_VALUE=$(echo "$API_OUTPUT" | jq -r --arg id "$SETTING" '.result[] | select(.id==$id) | .value')
        _debug "Setting value: $SETTING_VALUE"
        
        # If value is empty (setting not found), continue to next setting
        if [[ -z "$SETTING_VALUE" ]]; then
            _debug "Setting $SETTING not found in API response"
            continue
        fi
        
        # Apply special formatting for certain settings
        if [[ $SETTING == "challenge_ttl" ]]; then
            if [[ "$SETTING_VALUE" =~ ^[0-9]+$ ]]; then
                HUMAN_TIME=$(_convert_seconds "$SETTING_VALUE")
                SETTING_VALUE="$SETTING_VALUE ($HUMAN_TIME)"
            fi
        fi
        
        echo "${CF_SETTINGS[$SETTING]}: $SETTING_VALUE"
    done
}

# ==================================================
# -- _cf_set_settings $CF_ZONEID $SETTING $VALUE
# ==================================================
_cf_set_settings () {
    _debug "function:${FUNCNAME[0]} - ${*}"

	local CF_ZONE_ID=$1 SETTING=$2 VALUE=$3
	_debug "function:${FUNCNAME[0]}"
	_debug "Running _cf_set_settings() with ${*}"
	
	_running "Setting $SETTING to $VALUE"
    EXTRA=(-H "Content-Type: application/json" \
     --data 
    '{ "value": "'"$VALUE"'" }')        
	cf_api "PATCH" "/client/v4/zones/${CF_ZONE_ID}/settings/${SETTING}" "${EXTRA[@]}"
	if [[ $CURL_EXIT_CODE == "200" ]]; then
		_success "Success from API: $CURL_EXIT_CODE - $API_OUTPUT"
		echo "Completed setting $SETTING to $VALUE successfully"
		exit 0
	else		
		exit 1
	fi
}

# ==================================================
# -- _cf_check_setting $SETTING
# ==================================================
function _cf_check_setting () {
    local SETTING=${1}
    _debug "function:${FUNCNAME[0]}"
    _debug "Checking $SETTING"
    if [[ " ${!CF_SETTINGS[*]} " =~ " ${SETTING} " ]]; then
        _debug "$SETTING is in the list of allowed settings"
        return 0
    else
        _error "$SETTING is not in the list of allowed settings"        
        _error "Allowed settings are: ${!CF_SETTINGS[*]}"        
        return 1
    fi

}

# ==================================================
# -- _cf_check_setting_value $SETTING $VALUE
# ==================================================
function _cf_check_setting_value () {
    # -- Array for each $SETTING and $VALUE is called $CF_SETTINGS_VALUES
    local SETTING=${1^^}
    local VALUE=$2
    _debug "function:${FUNCNAME[0]}"
    _debug "Checking $SETTING with value $VALUE"
    local CF_SETTINGS_VALUES
    # Load up CF_SETTINGS_{SETTING} array into $CF_SETTINGS_VALUES
    eval "CF_SETTINGS_VALUES=(\"\${CF_DEFAULTS_${SETTING}[@]}\")"
    _debug "Allowed values for $SETTING are: ${CF_SETTINGS_VALUES[*]}"
    

    # -- Check if $VALUE is in $CF_SETTINGS_VALUES
    if [[ " ${CF_SETTINGS_VALUES[*]} " =~ " ${VALUE} " ]]; then
        _debug "Value $VALUE is in $SETTING"
        return 0
    else
        _error "Value $VALUE is not in $SETTING"
        _error "Allowed values for $SETTING are: ${CF_SETTINGS_VALUES[*]}"
        return 1
    fi
}

# ==================================================
# -- _cf_settings_values $SETTING
# ==================================================
function _cf_settings_values () {
    local SETTING=${1^^}
    _debug "function:${FUNCNAME[0]}"
    _debug "Getting values for $SETTING"
    local CF_SETTINGS_VALUES
    # Load up CF_SETTINGS_{SETTING} array into $CF_SETTINGS_VALUES
    eval "CF_SETTINGS_VALUES=(\"\${CF_DEFAULTS_${SETTING}[@]}\")"
    _debug "Allowed values for $SETTING are: ${CF_SETTINGS_VALUES[*]}"

    if [[ $SETTING == "CHALLENGE_TTL" ]]; then
        echo "Possible Values:"
        for SECONDS in "${CF_SETTINGS_VALUES[@]}"; do
            echo -e "\t$SECONDS - $(_convert_seconds $SECONDS)"
        done            
    else
        echo "Possible Values: ${CF_SETTINGS_VALUES[*]}"
    fi   
}
