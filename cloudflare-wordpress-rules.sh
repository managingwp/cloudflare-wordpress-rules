#!/bin/bash

# -- variables
# ------------
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEBUG="0"
DOMAIN=$1
CMD=$2
ID=$3

# -- Colors
RED="\e[31m"
GREEN="\e[32m"
BLUEBG="\e[44m"
YELLOWBG="\e[43m"
GREENBG="\e[42m"
DARKGREYBG="\e[100m"
ECOL="\e[0m"


# -- _error
_error () {
	echo -e "${RED}** ERROR ** - $@ ${ECOL}"
}

_success () {
    echo -e "${GREEN}** SUCCESS ** - $@ ${ECOL}"
}

_running () {
	echo -e "${BLUEBG}${@}${ECOL}"
}

_creating () {
	echo -e "${DARKGREYBG}${@}${ECOL}"
}

_separator () {
    echo -e "${YELLOWBG}****************${ECOL}"
}

_debug () {
	if [ -f $SCRIPT_DIR/.debug ]; then
		echo "DEBUG: $@"
	fi
}

_debug_json () {
    if [ -f $SCRIPT_DIR/.debug ]; then
        echo $@ | jq
    fi
}

usage () {
	echo "$0 <domain.com> <cmd> <id>"
	echo ""
	echo "Commands"
	echo "   create-rules <profile>     - Create rules on domain"
	echo "   get-rules                  - Get rules"
	echo "   delete-rule                - Delete rule"
	echo "   delete-filter <id>         - Delete rule ID on domain"
	echo "   get-filters                - Get Filters"
	echo "   get-filter-id <id>         - Get Filter <id>"
	echo ""
	echo "Profiles"
	echo "   protect-wp                 - The 5 golden rules, see https://github.com/managingwp/cloudflare-wordpress-rules"
	echo ""
	echo "Examples"
	echo "   $0 testdomain.com delete-filter 32341983412384bv213v"
	echo "   $0 testdomian.com create-rules"
	echo ""
	echo "Cloudflare API Credentials should be placed in \$HOME/.cloudflare"
	echo ""
}

# -- Get domain zoneid
# --------------------
# CF_GET_ZONEID $CF_ZONE
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
		    echo "  - Found $ZONE - ${CF_ZONEID}"
		fi
	fi
}
	

# -- Create filter
# -----------------
# CF_CREATE_FILETER $CF_EXPRESSION
CF_CREATE_FILTER () {
	echo "  - Creating Filter - $1"
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
}

# -- Create rule
# --------------
CF_CREATE_RULE () {
	ID=$1
	ACTION=$2
	PRIORITY=$3
	DESCRIPTION=$4
	
	echo "  - Creating Rule with ID:$ID - ACTION:$ACTION PRIORITY:$PRIORITY - DESCRIPTION:$DESCRIPTION"
	CF_CREATE_RULE_CURL=$(curl -s -X POST \
	"https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/firewall/rules" \
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
	_debug CF_CREATE_RULE_CURL
	CF_CREATE_RULE_RESULT=$( echo $CF_CREATE_RULE_CURL | jq -r '.success')
	if [[ $CF_CREATE_RULE_RESULT == "false" ]]; then
		_error "Error creating Cloudflare filter"
        echo $CF_CREATE_RULE_CURL
        exit 1
    else
    	echo " -- Created Rule Successfully"
    fi	
}

# -- Get Filters
# CF_GET_FILTERS
# --------------
CF_GET_FILTERS () {	
    CF_GET_FILTERS_CURL=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/filters" \
    -H "X-Auth-Email: ${CF_ACCOUNT}" \
    -H "X-Auth-Key: ${CF_TOKEN}" \
    -H "Content-Type: application/json")
    _debug_json $CF_GET_FILTERS_CURL
    echo $CF_GET_FILTERS_CURL | jq -r
}

# -- Get Filter ID
# CF_GET_FILTER_ID ${CF_FILTER_ID}
# --------------
CF_GET_FILTER_ID () {
    CF_GET_FILTER_ID_CURL=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/filters/${1}" \
    -H "X-Auth-Email: ${CF_ACCOUNT}" \
    -H "X-Auth-Key: ${CF_TOKEN}" \
    -H "Content-Type: application/json")
    _debug_json $CF_GET_FILTER_ID_CURL
}

# -- Delete filters
# CF_DELETE_FILTER ${CF_FILTER_ID}
# -----------------
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

# -- Get rules
# CF_GET_RULES
# ------------
CF_GET_RULES () {
    CF_GET_RULES_CURL=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/firewall/rules" \
    -H "X-Auth-Email: ${CF_ACCOUNT}" \
    -H "X-Auth-Key: ${CF_TOKEN}" \
    -H "Content-Type: application/json")
    _debug_json $CF_GET_RULES_CURL
    echo $CF_GET_RULES_CURL | jq -r
}

# -- Delete rule
# CF_DELETE_RULE $CF_ZONEID
# ------------
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

# -- Protect WordPress
# --------------------
CF_PROTECT_WP () {
	# -- Block xmlrpc.php - Priority 1
	_creating "  Creating - Block xml-rpc.php rule"
	CF_CREATE_FILTER 'http.request.uri.path eq \"/xmlrpc.php\"'
	if [[ $? == "0" ]]; then
	    CF_CREATE_RULE "$CF_CREATE_FILTER_ID" "block" "1" "Block URI Query, URL, User Agents, and IPs (Block)"
	fi
	_separator

	# -- Allow URI Query, URL, User Agents, and IPs (Allow) - Priority 2
	_creating "  Creating - Allow URI Query, URL, User Agents, and IPs (Allow)"
    BLOG_VAULT_IPS_A=(" 88.99.145.111
88.99.145.112
195.201.197.31
136.243.130.174
144.76.236.242
136.243.130.52
116.202.131.150
116.202.233.15
116.202.193.3
168.119.2.157
49.12.124.233
88.99.146.248
139.180.140.55
104.248.114.9
192.81.221.63
45.63.10.187
45.76.137.73
45.76.183.23
159.223.99.132
198.211.127.63
45.76.126.238
159.223.105.100
161.35.121.79
208.68.38.165
147.182.131.77
174.138.35.170
149.28.228.237
45.77.106.232
140.82.15.60
108.61.142.158
45.77.220.240
67.205.160.142
137.184.156.126
157.245.142.130
159.223.127.73
198.211.127.43
198.211.123.140
82.196.0.67
188.166.158.7
46.101.79.124
192.248.168.22
78.141.225.57
95.179.214.63
104.238.190.161
95.179.208.185
95.179.220.182
66.135.5.151
45.32.7.254
149.28.227.238
8.9.37.67
149.28.231.28
142.132.211.19
142.132.211.18
142.132.211.17
159.223.166.150
167.172.146.73
143.198.184.39
161.35.123.156
147.182.139.65
198.211.125.219
185.14.187.177
192.81.222.35
209.97.131.196
209.97.135.165
104.238.170.64
78.141.244.3
217.69.0.229
45.63.115.86
108.61.123.152
45.32.144.195
140.82.12.121
45.77.99.218
45.63.11.48
149.28.45.216
209.222.10.118")
	BLOG_VAULT_IPS_B=$(echo $BLOG_VAULT_IPS_A|tr "\n" " ")
    WP_UMBRELLA="141.95.192.2"
    echo '(ip.src in { '"${BLOG_VAULT_IPS_B}"' '"${WP_UMBRELLA}"'})'
	CF_CREATE_FILTER '(ip.src in { '"${BLOG_VAULT_IPS_B}"' }) or (ip.src in {'"${WP_UMBRELLA}"'})'
	if [[ $? == "0" ]]; then
		CF_CREATE_RULE "$CF_CREATE_FILTER_ID" "allow" "2" "Allow URI Query, URL, User Agents, and IPs (Allow)"
	fi
	_separator

	# --  Managed Challenge /wp-admin (Managed Challenge) - Priority 3
	_creating "  Creating Managed Challenge /wp-admin (Managed Challenge) rule"
	CF_CREATE_FILTER '(http.request.uri.path contains \"/wp-login.php\") or (http.request.uri.path contains \"/wp-admin/\" and http.request.uri.path ne \"/wp-admin/admin-ajax.php\")'
	if [[ $? == "0" ]]; then
	    CF_CREATE_RULE "$CF_CREATE_FILTER_ID" "managed_challenge" "3" "Managed Challenge /wp-admin (Managed Challenge)"
	fi
	_separator
	
	# --  Allow Good Bots and User Agent/URI/URL Query (Allow) - Priority 4
	_creating "  Allow Good Bots and User Agent/URI/URL Query (Allow)"
	CF_CREATE_FILTER '(cf.client.bot) or (http.user_agent contains \"Metorik API Client\") or (http.user_agent contains \"Wordfence Central API\") or (http.request.uri.query contains \"wc-api=wc_shipstation\") or (http.user_agent eq \"Better Uptime Bot\") or (http.user_agent eq \"ShortPixel\") or (http.user_agent contains \"umbrella bot\")'
	if [[ $? == "0" ]]; then
	    CF_CREATE_RULE "$CF_CREATE_FILTER_ID" "allow" "4" "Allow Good Bots and User Agent/URI/URL Query (Allow)"
	fi
	_separator

	# -- Challenge Outside of GEO (JS Challenge)	
	_creating "  Challenge Outside of GEO (JS Challenge)"
	CF_CREATE_FILTER '(ip.geoip.country ne \"CA\")'
	if [[ $? == "0" ]]; then
		CF_CREATE_RULE "$CF_CREATE_FILTER_ID" "js_challenge" "5" "Challenge Outside of GEO (JS Challenge)"
	fi
	_separator

	_success "  Completed Protect WP profile"
}

# -------
# -- main
# -------

# -- Check for .cloudflare credentials.
if [[ -f ~/.cloudflare ]]; then
    source ~/.cloudflare
else
    _error "Can't find $HOME/.cloudflare exiting."
    exit 1
fi

# -- Show usage if no domain provided
if [[ -z $DOMAIN ]]; then
    usage
    exit 1
fi

# -- Check $CMD
if [[ -z $CMD ]]; then
	usage
	exit 1
elif [[ $CMD == "create-rules" ]]; then
	_running "  Running Create rules"
	CF_GET_ZONEID $DOMAIN
	CF_PROTECT_WP
elif [[ $CMD == "get-rules" ]]; then
    _running "  Running Get rules"
    CF_GET_ZONEID $DOMAIN
    CF_GET_RULES
elif [[ $CMD == "delete-rule" ]]; then
    _running "  Running Delete rule"
    CF_GET_ZONEID $DOMAIN
    CF_DELETE_RULE ${3}
elif [[ $CMD == "get-filters" ]]; then
	_running "  Running Get filters"
	CF_GET_ZONEID $DOMAIN
	CF_GET_FILTERS
elif [[ $CMD == "get-filter-id" ]]; then
    _running "  Running Get filter ID $3"
    if [[ -z $ID ]]; then
    	usage
    	exit 1
    else
        CF_GET_ZONEID $DOMAIN
    	CF_GET_FILTER_ID $3
    fi
elif [[ $CMD == "delete-filter" ]]; then
	if [[ -z $ID ]]; then
		usage
		exit 1
	else
		_running "  Running Delete filter"
		CF_GET_ZONEID $DOMAIN
		CF_DELETE_FILTER $ID
	fi
else
	usage 
	exit 1
fi
