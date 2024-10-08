# ==================================================
# -- Check bash version
# ==================================================
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
	_error "Bash version 4 or higher required"
	exit 1
fi

# -- Colors
BLACK="\033[30m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
BLUEBG="\033[0;44m"
YELLOWBG="\033[0;43m"
GREENBG="\033[0;42m"
DARKGREYBG="\033[0;100m"
DARKGREY="\033[0;90m"
ECOL="\033[0;0m"

# -- messages
_error () { echo -e "${RED}** ERROR ** - ${*} ${ECOL}"; }
_warning () { echo -e "${YELLOW}** WARNING ** - ${*} ${ECOL}"; }
_success () { echo -e "${GREEN}** SUCCESS ** - ${*} ${ECOL}"; }
_running () { echo -e "${YELLOWBG}${BLACK} * ${*}${ECOL}"; }
_running2 () { echo -e "${DARKGREY} * ${*}${ECOL}"; }
_creating () { echo -e "${DARKGREYBG} =+=+=+=+=+=+=+=+ ${*} =+=+=+=+=+=+=+=+${ECOL}"; }
_separator () { echo -e "${YELLOWBG}===========================================================================================================\n${ECOL}"; }
_dryrun () { echo -e "${CYAN}** DRYRUN: ${*$}{ECOL}"; }


# =================================================================================================
# -- debug
# =================================================================================================
function _debug () { 
	# Get the previous function name
	local FUNCTION
	FUNCTION=$(caller 1 | awk '{print $2}')
	if [[ $DEBUG == "1" ]]; then
		echo -e "${CYAN}** DEBUG: ${FUNCTION}: ${*}${ECOL}" >&2
	fi
}

# =================================================================================================
# -- debug_jsons
# =================================================================================================
function _debug_json () {
	local FUNCTION
	FUNCTION=$(caller 1 | awk '{print $2}')
    if [[ $DEBUG_JSON == "1" ]]; then
        echo -e "${CCYAN}** DEBUG_JSON: $FUNCTION: ${*}${NC}" >&2
        echo "${@}" | jq >&2
    fi
}