# ==================================================
# CF_GET_RULES $CF_ZONE_ID
# ==================================================
CF_GET_RULES () {
	local ZONE_ID=$1
    CF_GET_RULES_CURL=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/firewall/rules" \
    -H "X-Auth-Email: ${CF_ACCOUNT}" \
    -H "X-Auth-Key: ${CF_TOKEN}" \
    -H "Content-Type: application/json")
    _debug_json $CF_GET_RULES_CURL
    echo $CF_GET_RULES_CURL | jq -r
}

# ==================================================
# -- CF_DELETE_RULE $CF_ZONEID
# ==================================================
CF_DELETE_RULE () {
	while true; do
	    read -p "Delete rule ${1} ? (y|n)" yn
    	case $yn in
    		[Yy]* ) break;;
            [Nn]* ) exit;;
            * ) echo "Please answer yes or no.";;
        esac
    done
    CF_DELETE_RULE_CURL=$(curl -s -X DELETE \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/firewall/rules/${1}" \
    -H "X-Auth-Email: ${CF_ACCOUNT}" \
    -H "X-Auth-Key: ${CF_TOKEN}" \
    -H "Content-Type: application/json")
	    
    _debug_json $CF_DELETE_RULE_CURL
    echo $CF_DELETE_RULE_CURL | jq -r
}

# ==================================================
# -- CF_GET_FILTERS
# ==================================================
CF_GET_FILTERS () {	
    CF_GET_FILTERS_CURL=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/filters" \
    -H "X-Auth-Email: ${CF_ACCOUNT}" \
    -H "X-Auth-Key: ${CF_TOKEN}" \
    -H "Content-Type: application/json")
    _debug_json $CF_GET_FILTERS_CURL
    echo $CF_GET_FILTERS_CURL | jq -r
}

# ==================================================
# -- CF_GET_FILTER_ID ${CF_FILTER_ID}
# ==================================================
CF_GET_FILTER_ID () {
    CF_GET_FILTER_ID_CURL=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/filters/${1}" \
    -H "X-Auth-Email: ${CF_ACCOUNT}" \
    -H "X-Auth-Key: ${CF_TOKEN}" \
    -H "Content-Type: application/json")
    _debug_json $CF_GET_FILTER_ID_CURL
}

# ==================================================
# -- CF_DELETE_FILTER ${CF_FILTER_ID}
# ==================================================
CF_DELETE_FILTER () {
	FILTER=$@
	_debug "Filter: $FILTER"
	CF_DELETE_FILTERS_CURL=$(curl -s -X DELETE \
	"https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/filters/${1}" \
    -H "X-Auth-Email: ${CF_ACCOUNT}" \
    -H "X-Auth-Key: ${CF_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"id":"'"${FILTER}"'"}')
	_debug_json $CF_DELETE_FILTERS_CURL
	echo $CF_DELETE_FILTERS_CURL | jq -r
}



# ==================================================
# -- CF_DELETE_ALL_RULES $CF_ZONE_ID
# ==================================================
CF_DELETE_ALL_RULES () {
	echo "Not implemented yet"
}

# ==================================================
# -- CF_CREATE_FILETER $CF_ZONE_ID $CF_EXPRESSION
# ==================================================
CF_CREATE_FILTER () {
	local ZONE_ID=$1
	local CF_EXPRESSION=$2
	echo "  - Creating Filter - ${CF_EXPRESSION} on ${ZONE_ID}"
	# -- create_filter curl
	CF_API_ENDPOINT="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/filters"
	_debug "CF_API_ENDPOINT: $CF_API_ENDPOINT"
	CF_CREATE_FILTER_CURL="curl -s -X POST ${CF_API_ENDPOINT} -H \"X-Auth-Email: ${CF_ACCOUNT}\" -H \"X-Auth-Key: ${CF_TOKEN}\" -H \"Content-Type: application/json\"
	-d '[
  { 
    \"expression\": '$CF_EXPRESSION'
  }
  ]'"
	_debug "CF_CREATE_FILTER_CURL: $CF_CREATE_FILTER_CURL"
    CF_CREATE_FILTER_CURL_OUTPUT="$($CF_CREATE_FILTER_CURL)"
    _debug $CF_CREATE_FILTER_CURL_OUTPUT
	
	if [[ $DRYRUN == "1" ]];then
		_dryrun " ** DRYRUN: URL = ${CF_API_ENDPOINT}"
		_dryrun " ** DRYRUN: expression = ${CF_EXPRESSION}"
	else
		# -- Confirm successful command
		CF_CREATE_FILTER_RESULT=$( echo $CF_CREATE_FILTER_CURL | jq -r '.success')
	    if [[ $CF_CREATE_FILTER_RESULT == "false" ]]; then
			# -- Grabbing error message.
			CF_CREATE_FILTER_ERROR=$( echo $CF_CREATE_FILTER_CURL | jq -r '.errors[] | "\(.message)"')

			# -- Duplicate filter found
			if [[ $CF_CREATE_FILTER_ERROR == "config duplicates an already existing config" ]]; then
				_error "A filter exists with this filter, skipping"
				CF_FILTER_ID=$( echo $CF_CREATE_FILTER_CURL | jq -r '.errors[] | "\(.meta.id)"')			
				_error "Error ID = $CF_FILTER_ID"
				CF_GET_FILTER_ID $CF_FILTER_ID
				while true; do
					read -p "Delete above mentioned filter $CF_FILTER_ID? (y|n)" yn
				    case $yn in
				        [Yy]* ) CF_DELETE_FILTER $CF_FILTER_ID; break;;
				        [Nn]* ) echo "  - Skipping";break;;
				        * ) echo "Please answer yes or no.";;
			    	esac
				done
				return 1
			else
				_error "Error creating Cloudflare filter"
		        exit 1
		    fi
	    else
	    	CF_CREATE_FILTER_ID=$(echo $CF_CREATE_FILTER_CURL | jq -r '.result[] | "\(.id)"')
	    	if [[ -z $CF_CREATE_FILTER_ID ]]; then
    			_error "No Cloudflare filter id provided, api error"
    			exit 1
    		else
	    		_success "  - Successfully Created Cloudflare Filter ID - $CF_CREATE_FILTER_ID"
    		fi
	    fi
    fi
}

# ==================================================
# -- CF_CREATE_RULE $CF_ZONEID $ACTION $PRIORITY $DESCRIPTION
# ==================================================
CF_CREATE_RULE () {
	ZONE_ID=$1
	ID=$2
	ACTION=$3
	PRIORITY=$4
	DESCRIPTION=$5

	echo " - Creating Rule with ID:$ID - ACTION:$ACTION PRIORITY:$PRIORITY - DESCRIPTION:$DESCRIPTION"
	CF_API_ENDPOINT="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/firewall/rules"
    if [[ $DRYRUN == "1" ]]; then
        _dryrun "URL = ${CF_API_ENDPOINT}"
    else
	    CF_CREATE_RULE_CURL=$(curl -s -X POST "${CF_API_ENDPOINT}" \
		-H "X-Auth-Email: ${CF_ACCOUNT}" \
		-H "X-Auth-Key: ${CF_TOKEN}" \
		-H "Content-Type: application/json" \
	-d '[
  {
    "filter": {
      "id": "'"${ID}"'"
    },
    "action": "'"${ACTION}"'",
    "priority": '"${PRIORITY}"',
    "description": "'"${DESCRIPTION}"'"
  }
]')
    
		CF_CREATE_RULE_RESULT=$( echo $CF_CREATE_RULE_CURL | jq -r '.success')
		if [[ $CF_CREATE_RULE_RESULT == "false" ]]; then
		 	_error "Error creating Cloudflare filter"
	        echo $CF_CREATE_RULE_CURL
    	    exit 1
	    else
    		echo " -- Created Rule Successfully"
	    fi	
	fi
}

