#!/bin/bash

# -- variables
# ------------
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SCRIPT_NAME="cloudflare-wordpress-rules"
VERSION=$(cat "${SCRIPT_DIR}/VERSION")
DEBUG="0"
DRYRUN="0"
PROFILE_DIR="${SCRIPT_DIR}/profiles"

# -- Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[0;93m"
BLUEBG="\033[0;44m"
YELLOWBG="\033[0;43m"
YELLOW="\033[0;93m"
GREENBG="\033[0;42m"
DARKGREYBG="\033[0;100m"
ECOL="\033[0;0m"

# -- messages
_error () { echo -e "${RED}** ERROR ** - ${*} ${ECOL}"; }
_success () { echo -e "${GREEN}** SUCCESS ** - ${*} ${ECOL}"; }
_running () { echo -e "${BLUEBG} * ${*}${ECOL}"; }
_warning () { echo -e "${YELLOW}** WARNING ** - ${*} ${ECOL}"; } # _warning
_creating () { echo -e "${DARKGREYBG}${*}${ECOL}"; }
_separator () { echo -e "${YELLOWBG}****************${ECOL}"; }
_dryrun () { echo -e "${CYAN}** DRYRUN: ${*$}{ECOL}"; }


# -- debug
_debug () { 
	if [[ $DEBUG == "1" ]]; then
		echo -e "${CYAN}** DEBUG: ${*}${ECOL}"
	fi
}

_debug_json () {
    if [ -f $SCRIPT_DIR/.debug ]; then
        echo "${*}" | jq
    fi
}

# -- usage
usage () {
	echo "Usage: $SCRIPT_NAME (-d|-dr) <command>"
	echo ""
	echo " Options"
	echo "   -d                         - Debug mode"
	echo "   -dr                        - Dry run, don't send to Cloudflare"
	echo ""
	echo " Commands"
	echo "   create-rules <domain> <profile>    - Create rules on domain using <profile> if none specified default profile will be used"
	echo "   get-rules <domain>                 - Get rules"
	echo "   delete-rule <id>                   - Delete rule"
	echo "   delete-filter <id>                 - Delete rule ID on domain"
	echo "   get-filters <id>                   - Get Filters"
	echo "   get-filter-id <id>                 - Get Filter <id>"
	echo ""
	echo " Profiles - See profiles directory for examples ** Not yet functional**"
	echo "   default                            - Based on https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/cloudflare-protect-wordpress.md"
	echo ""
	echo ""
	echo "Examples"
	echo "   $SCRIPT_NAME delete-filter domain.com 32341983412384bv213v"
	echo "   $SCRIPT_NAME create-rules domain.com"
	echo ""
	echo "Cloudflare API Credentials should be placed in \$HOME/.cloudflare"
	echo ""
	echo "Version: $VERSION"
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
			# Check to see if two ids are in CF_ZONEID, zones are separated by newlines
			ZONES_RETURNED=$(echo "$CF_ZONEID" | wc -l)			
			if [[ ZONES_RETURNED -gt 1 ]]; then
				_warning "Found multiple zones for $ZONE"
				# List each zone with a number, zoneid and account email
				i=1
				echo "$CF_ZONEID" | while read -r ZONE; do
					ZONE_ID=$(echo "$ZONE" | awk '{print $1}')
					ZONE_NAME=$(_cf_zone_account_email $ZONE_ID)
					echo "$i - Zone ID: $ZONE_ID - $ZONE_NAME"
					i=$((i+1))
				done
				echo

				# Ask user to select the correct zone
				read -p "Please select the correct zone id: " SELECTED_ZONE
				# Make sure the selected zone is a number
				if [[ ! $SELECTED_ZONE =~ ^[0-9]+$ ]]; then
					_error "Invalid selection"
					exit 1
				fi
				# Confirm selected zone is in the list
				if [[ $SELECTED_ZONE -gt $ZONES_RETURNED ]]; then
					_error "Invalid selection"
					exit 1
				fi
				echo

				# Set CF_ZONEID to the selected zone based on number
				CF_ZONEID=$(echo "$CF_ZONEID" | awk -v SELECTED_ZONE=$SELECTED_ZONE 'NR==SELECTED_ZONE {print $1}')				
			else
				_success "Found Zone ID $CF_ZONEID for $ZONE"
			fi		    
		fi
	fi
}
	

# -- Create filter
# -----------------
# CF_CREATE_FILETER $CF_EXPRESSION
CF_CREATE_FILTER () {
	CF_EXPRESSION=$1
	echo "  - Creating Filter - ${CF_EXPRESSION} on ${CF_ZONEID}"
	# -- create_filter curl
	CF_API_ENDPOINT="https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/filters"
	CF_CREATE_FILTER_CURL=$(curl -s -X POST ${CF_API_ENDPOINT} \
	-H "X-Auth-Email: ${CF_ACCOUNT}" \
	-H "X-Auth-Key: ${CF_TOKEN}" \
	-H "Content-Type: application/json" \
	-d '[
  { 
    "expression": "'"$CF_EXPRESSION"'"
  }
  ]')
	
	_debug "${CF_CREATE_FILTER_CURL}"
	
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

# -- Create rule
# --------------
CF_CREATE_RULE () {
	ID=$1
	ACTION=$2
	PRIORITY=$3
	DESCRIPTION=$4

	echo " - Creating Rule with ID:$ID - ACTION:$ACTION PRIORITY:$PRIORITY - DESCRIPTION:$DESCRIPTION"
	CF_API_ENDPOINT="https://api.cloudflare.com/client/v4/zones/${CF_ZONEID}/firewall/rules"
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

# -- cf_profile_create <profile-name>
cf_profile_create () {
	PROFILE_NAME=$1
	
	# -- Check if profile dir exists
	if [[ ! -d $PROFILE_DIR ]]; then
		_error "$PROFILE_DIR doesn't exist, failing"	
		exit 1
	fi
	
	# -- Create rules
	echo "poop"		
}

# -- Protect WordPress
# --------------------
CF_PROTECT_WP () {
	# -- Block xmlrpc.php - Priority 1
	_creating "  Creating - Block xml-rpc.php rule on $DOMAIN - $ZONEID"
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
	CF_CREATE_FILTER '(http.request.uri.path contains \"/wp-login.php\") or (http.request.uri.path contains \"/wp-admin/\" and http.request.uri.path ne \"/wp-admin/admin-ajax.php\" and not http.request.uri.path contains \"/wp-admin/js/password-strength-meter.min.js\")'
	if [[ $? == "0" ]]; then
	    CF_CREATE_RULE "$CF_CREATE_FILTER_ID" "managed_challenge" "3" "Managed Challenge /wp-admin (Managed Challenge)"
	fi
	_separator
	
	# --  Allow Good Bots and User Agent/URI/URL Query (Allow) - Priority 4
	_creating "  Allow Good Bots and User Agent/URI/URL Query (Allow)"
	CF_CREATE_FILTER '(cf.client.bot) or (http.user_agent contains \"Metorik API Client\") or (http.user_agent contains \"Wordfence Central API\") or (http.request.uri.query contains \"wc-api=wc_shipstation\") or (http.user_agent eq \"Better Uptime Bot\") or (http.user_agent eq \"ShortPixel\") or (http.user_agent contains \"WPUmbrella\")'
	if [[ $? == "0" ]]; then
	    CF_CREATE_RULE "$CF_CREATE_FILTER_ID" "allow" "4" "Allow Good Bots and User Agent/URI/URL Query (Allow)"
	fi
	_separator

	# -- Challenge Outside of GEO (JS Challenge)	
	_creating "  Challenge Outside of GEO (JS Challenge)"
	CF_CREATE_FILTER '(not ip.geoip.country in {\"CA\" \"US\"})'
	if [[ $? == "0" ]]; then
		CF_CREATE_RULE "$CF_CREATE_FILTER_ID" "js_challenge" "5" "Challenge Outside of GEO (JS Challenge)"
	fi
	_separator

	_success "  Completed Protect WP profile"
}

# -- Create Profile
cf_create_profile () {
	echo " * Creating profile $1"
	
}

# -- _cf_zone_account_email
_cf_zone_account_email () {
	ZONE_ID=$1
	CF_ZONE_ACCOUNT_EMAIL=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}" \
	-H "X-Auth-Email: ${CF_ACCOUNT}" \
	-H "X-Auth-Key: ${CF_TOKEN}" \
	-H "Content-Type: application/json")
	echo $CF_ZONE_ACCOUNT_EMAIL | jq -r '.result | "\(.name) \(.account.name)"'
}

# -------
# -- main
# -------

# -- Parse options
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
        *)    # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        ;;
    esac
    done
set -- "${POSITIONAL[@]}" # restore positional parameters

# -- Commands
_debug "ARGS: ${*}@"
DOMAIN=$2
CMD=$1
PROFILE=$3
ID=$3

# -- Dryrun
if [[ $DRYRUN = "1" ]]; then
	_error "Dryrun not implemented yet"
fi

# -- Check for .cloudflare credentials
if [ ! -f "$HOME/.cloudflare" ]; then
		echo "No .cloudflare file."
	if [ -z "$CF_ACCOUNT" ]; then
		_error "No \$CF_ACCOUNT set."
		usage
		exit 1
	fi
	if [ -z "$CF_TOKEN" ]; then
		_error "No \$CF_TOKEN set."
		usage
		exit 1
	fi
else
	_debug "Found .cloudflare file."
	source $HOME/.cloudflare
	_debug "Sourced CF_ACCOUNT: $CF_ACCOUNT CF_TOKEN: $CF_TOKEN"
        if [ -z "$CF_ACCOUNT" ]; then
                _error "No \$CF_ACCOUNT set in config."
                usage
				exit 1
        fi
        if [ -z "$CF_TOKEN" ]; then
                _error "No \$CF_TOKEN set in config.

        $USAGE"
        fi
fi

# -- Show usage if no domain provided
if [[ -z $DOMAIN ]]; then
    usage
    _error "No domain provided"
    exit 1
fi

# -- Check $CMD
if [[ -z $CMD ]]; then
	usage
	_error "No command provided"
	exit 1
# -- create-rules
elif [[ $CMD == "create-rules" ]]; then
	_running "Running Create rules"
	if [[ -z $PROFILE ]]; then
		_running "Missing profile name, using default for rules"
		CF_GET_ZONEID $DOMAIN
		CF_PROTECT_WP # @ISSUE needs to be migrated
	else
		_running "Creating rules using profile $PROFILE"
		cf_profile_create $PROFILE
	fi
# -- custom-rules
elif [[ $CMD == "custom-rules" ]]; then
	_running "Running custom-rules"
	CF_GET_ZONEID $DOMAIN
	cf_custom_rules $PROFILE
# -- get-rules
elif [[ $CMD == "get-rules" ]]; then
    _running "  Running Get rules"
    CF_GET_ZONEID $DOMAIN
    CF_GET_RULES
# -- delete-rules
elif [[ $CMD == "delete-rule" ]]; then
    _running "  Running Delete rule"
    CF_GET_ZONEID $DOMAIN
    CF_DELETE_RULE ${3}
# -- get-filters
elif [[ $CMD == "get-filters" ]]; then
	_running "  Running Get filters"
	CF_GET_ZONEID $DOMAIN
	CF_GET_FILTERS
# -- get-filter-id
elif [[ $CMD == "get-filter-id" ]]; then
    _running "  Running Get filter ID $3"
    if [[ -z $ID ]]; then
    	usage
    	_error "No rule ID provided"
    	exit 1
    else
        CF_GET_ZONEID $DOMAIN
    	CF_GET_FILTER_ID $3
    fi
# -- delete-filter
elif [[ $CMD == "delete-filter" ]]; then
	if [[ -z $ID ]]; then
		usage
		_error "No rule ID provided"
		exit 1
	else
		_running "  Running Delete filter"
		CF_GET_ZONEID $DOMAIN
		CF_DELETE_FILTER $ID
	fi
else
	usage 
	_error "No command provided"
	exit 1
fi
