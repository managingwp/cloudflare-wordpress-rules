#!/bin/bash

# -- variables
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEBUG="0"
ZONE=$1

# -- _error
_error () {
	echo " *ERROR* - $@"
}

_debug () {
	if [ -f $SCRIPT_DIR/.debug ]; then
		echo "DEBUG: $@"
	fi
}

usage () {
	echo "$0 <domain.com>"
}

# -- Get domain zoneid
CF_GET_ZONEID () {
    ZONE=$1
    CF_ZONEID_CURL=$(curl -s -X GET 'https://api.cloudflare.com/client/v4/zones/?per_page=500' \
    -H "X-Auth-Email: ${CF_ACCOUNT}" \
    -H "X-Auth-Key: ${CF_TOKEN}" \
    -H "Content-Type: application/json")
    CF_ZONEID_RESULT=$( echo $CF_ZONEID_CURL | jq -r '.success')
	if [[ $CF_ZONEID_RESULT == "false" ]]; then
		_error "Error getting Cloudflare Zone ID"
		echo $CF_ZONEID_CURL
		exit 1
	else
		CF_ZONEID=$( echo $CF_ZONEID_CURL | jq -r '.result[] | "\(.id) \(.name)"'| grep "$ZONE" | awk {' print $1 '})
		if [[ -z $CF_ZONEID ]]; then
			_error "Couldn't find domain $ZONE"
			exit 1
		else
		    echo "Found $ZONE - ${CF_ZONEID}"
		fi
	fi
}
	

# -- Create filters
CF_CREATE_FILTER () {
	echo " - Creating Filter - $1"
	CF_CREATE_FILTER_CURL=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/filters" \
	-H "X-Auth-Email: ${CF_ACCOUNT}" \
	-H "X-Auth-Key: ${CF_TOKEN}" \
	-H "Content-Type: application/json" \
	-d '[
  { 
    "expression": "'"$1"'"
  }
  ]')
	CF_CREATE_FILTER_RESULT=$( echo $CF_CREATE_FILTER_CURL | jq -r '.success')
    if [[ $CF_CREATE_FILTER_RESULT == "false" ]]; then
		# -- Grabbing error message.
		CF_CREATE_FILTER_ERROR=$( echo $CF_CREATE_FILTER_CURL | jq -r '.errors[] | "\(.message)"')
		if [[ $CF_CREATE_FILTER_ERROR == "config duplicates an already existing config" ]]; then
			_error "A filter exists with this filter, skipping"
			return 1
		else
			_error "Error creating Cloudflare filter"
    	    echo $CF_CREATE_FILTER_CURL
	        exit 1
	    fi
    else
    	CF_CREATE_FILTER_ID=$(echo $CF_CREATE_FILTER_CURL | jq -r '.result[] | "\(.id)"')
    	if [[ -z $CF_CREATE_FILTER_ID ]]; then
    		_error "No Cloudflare filter id provided, api error"
    		exit 1
    	else
    		echo " -- Created Cloudflare Filter ID - $CF_CREATE_FILTER_ID"
    	fi
    fi
}

# -- Create rule
CF_CREATE_RULE () {
	echo " - Creating Rule with ${1} - ${2} - ${3}"
	CF_CREATE_RULE_CURL=$(curl -s -X POST \
	"https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/firewall/rules" \
	-H "X-Auth-Email: ${CF_ACCOUNT}" \
	-H "X-Auth-Key: ${CF_TOKEN}" \
	-H "Content-Type: application/json" \
-d '[
  {
    "filter": {
      "id": "'"${1}"'"
    },
    "action": "'"${2}"'",
    "description": "'"${3}"'"
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
}

# -- main
if [[ -f ~/.cloudflare ]]; then
    source ~/.cloudflare
else
    _error "Can't find $HOME/.cloudflare exiting."
    exit 1
fi

if [[ -z $1 ]]; then
    usage
    exit 1
fi

CF_GET_ZONEID $ZONE

# -- Block xmlrpc.php
echo "Creating block xml-rpc.php rule"
CF_CREATE_FILTER 'http.request.uri.path eq \"/xmlrpc.php\"'
if [[ $? -eq "0" ]];then
	CF_CREATE_RULE "$CF_CREATE_FILTER_ID" "block" "Block URI Query, URL, User Agents, and IPs (Block)"
fi
echo ""

# --  Managed Challenge /wp-admin (Managed Challenge)
echo "Creating Managed Challenge /wp-admin (Managed Challenge) rule"
CF_CREATE_FILTER '(http.request.uri.path contains \"/wp-login.php\") or (http.request.uri.path contains \"/wp-admin/\" and http.request.uri.path ne \"/wp-admin/admin-ajax.php\")'
if [[ $? -eq "0" ]];then
	CF_CREATE_RULE "$CF_CREATE_FILTER_ID" "managed_challenge" "Managed Challenge /wp-admin (Managed Challenge)"
fi
echo ""
