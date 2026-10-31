#!/usr/bin/env bash
# =============================================================================
# cfwr.sh — the Cloudflare WordPress Rules entry point
#
# v1 (cfwrv1.sh) is the stable CLI. v2 (cfwrv2.sh) is the single-file refactor
# still in progress. This wrapper explains that, then runs the version you pick.
#
#   ./cfwr.sh                 choose a version (prompts on a terminal, else v1)
#   ./cfwr.sh -v2 …           force v2
#   CWR_VERSION=2 ./cfwr.sh … force v2 without the flag
#
# The banner and menu go to stderr, so `cfwr.sh … --json | jq` stays clean.
# =============================================================================

# ==================================
# -- Variables
# ==================================
SCRIPT_NAME="cfwr"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# ==================================
# -- bash-ui (vendored at the repo root)
# ==================================
_ui_lib=${BASH_UI:-}
if [[ -z $_ui_lib ]]; then
	_ui_dir=$SCRIPT_DIR
	while [[ $_ui_dir != '/' && $_ui_dir != '.' ]]; do
		if [[ -r $_ui_dir/vendor/bash-ui/ui.sh ]]; then
			_ui_lib=$_ui_dir/vendor/bash-ui/ui.sh
			break
		fi
		_ui_dir=$(dirname "$_ui_dir")
	done
fi
# shellcheck source=/dev/null
if [[ -n $_ui_lib ]]; then
	source "$_ui_lib"
fi
if ! command -v ui_ok >/dev/null 2>&1; then
	ui_ok() { printf 'OK: %s\n' "$*" >&2; }
	ui_warn() { printf 'WARN: %s\n' "$*" >&2; }
	ui_err() { printf 'ERR: %s\n' "$*" >&2; }
	ui_die() { printf 'ERR: %s\n' "$*" >&2; exit "${2:-1}"; }
	ui_step() { printf '> %s\n' "$*" >&2; }
	ui_info() { printf '%s\n' "$*" >&2; }
	ui_section() { printf '== %s ==\n' "$*" >&2; }
	ui_header() { printf '== %s ==\n' "${1:-}" >&2; }
	ui_kv() { printf '  %-14s %s\n' "${1:-}" "${2:-}" >&2; }
	ui_list() { printf '  - %s\n' "$@" >&2; }
	ui_hr() { printf '%s\n' '----------------------------------------' >&2; }
fi
# shellcheck disable=SC2034  # read by ui_header inside vendor/bash-ui/ui.sh
UI_APP_NAME="cfwr"

# ==================================
# -- usage
# ==================================
usage () {
	ui_header "Cloudflare WordPress Rules" "v1 is the stable CLI · v2 is the refactor in progress"
	ui_section "Usage"
	ui_list "$SCRIPT_NAME [-v1|-v2] -d <domain> -c <command> [options]" "$SCRIPT_NAME [-v1|-v2] <command> [options] -d <domain>"
	ui_section "Versions"
	# shellcheck disable=SC2034  # read by ui_kv inside vendor/bash-ui/ui.sh
	local UI_KV_WIDTH=22
	ui_kv "-v1, --v1" "cfwrv1.sh — stable, the released CLI"
	ui_kv "-v2, --v2" "cfwrv2.sh — the single-file refactor, still in progress"
	ui_kv "CWR_VERSION=1|2" "Same as the flag, for scripts and cron"
	ui_section "Behaviour"
	ui_list "With no version flag, a terminal prompts (default v1)" \
		"A pipe, cron job or CI run uses v1 without prompting" \
		"The chosen script's own -h shows its full command list"
	ui_section "Examples"
	ui_list "$SCRIPT_NAME -d example.com -c create-rules default" \
		"$SCRIPT_NAME -v2 -d example.com -c list-rules --json" \
		"CWR_VERSION=2 $SCRIPT_NAME list-profiles"
}

# ==================================
# -- Version selection
# ==================================
# The flag is consumed here and never reaches the script underneath.
version=""
declare -a ARGS=()
for arg in "$@"; do
	case $arg in
		-v1 | --v1) version=1 ;;
		-v2 | --v2) version=2 ;;
		-v[0-9]* | --v[0-9]*)
			ui_err "Unknown version: $arg (use -v1 or -v2)"
			exit 2
			;;
		*) ARGS+=("$arg") ;;
	esac
done

# ==================================
# -- v1 has no positional-command form: turn a leading command word into -c
# ==================================
V1_COMMANDS="create-rules update-rules upgrade-default-rules list-rules delete-rule delete-rules list-profiles print-profile validate-profile list-filters get-filter delete-filter delete-filters list-rulesets get-ruleset get-ruleset-fw-custom ruleset-get-entrypoint ruleset-add-rule ruleset-update-rule ruleset-delete-rule migrate-to-rulesets get-settings set-settings list-auth-profiles"

normalise_v1_args () {
	local -a out=()
	local skip_next=0 has_command=0
	for arg in "${ARGS[@]}"; do
		if (( skip_next )); then
			out+=("$arg")
			skip_next=0
			continue
		fi
		case $arg in
			-c | --command)
				has_command=1
				out+=("$arg")
				skip_next=1
				;;
			-d | --domain | -zf | --zones-file | --config | --cf-profile | --cf-auth-profile | --challenge-ttl)
				out+=("$arg")
				skip_next=1
				;;
			*)
				if (( !has_command )) && [[ " $V1_COMMANDS " == *" $arg "* ]]; then
					out+=("-c" "$arg")
					has_command=1
				else
					out+=("$arg")
				fi
				;;
		esac
	done
	ARGS=("${out[@]}")
}

# ==================================
# -- Run the chosen script
# ==================================
run_version () {
	local chosen=$1
	if [[ ! -r "$SCRIPT_DIR/cfwrv${chosen}.sh" ]]; then
		ui_err "cfwrv${chosen}.sh was not found next to $SCRIPT_NAME"
		exit 2
	fi
	if [[ $chosen == 1 ]]; then
		normalise_v1_args
	fi
	exec bash "$SCRIPT_DIR/cfwrv${chosen}.sh" "${ARGS[@]}"
}

if [[ -n $version ]]; then
	run_version "$version"
fi

# -h/--help before picking a version describes the wrapper itself
for arg in "${ARGS[@]}"; do
	if [[ $arg == "-h" || $arg == "--help" ]]; then
		usage
		exit 0
	fi
done

if [[ -n ${CWR_VERSION:-} ]]; then
	case $CWR_VERSION in
		1 | 2) version=$CWR_VERSION ;;
		*)
			ui_err "CWR_VERSION must be 1 or 2, got '${CWR_VERSION}'"
			exit 2
			;;
	esac
fi

if [[ -z $version ]]; then
	if [[ -t 0 && -t 2 && -z ${CI:-} ]]; then
		ui_header "Cloudflare WordPress Rules" "v1 is the stable CLI · v2 is the refactor in progress"
		ui_section "Choose a version"
		ui_list "1) v1 — stable, the released CLI" "2) v2 — the single-file refactor, still in progress"
		printf 'Version [1]: ' >&2
		reply=""
		read -r reply || reply=""
		case $reply in
			2) version=2 ;;
			"" | 1) version=1 ;;
			*)
				ui_err "Unknown choice: $reply (use 1 or 2)"
				exit 2
				;;
		esac
	else
		version=1
		ui_info "Running v1 (stable); force v2 with -v2 or CWR_VERSION=2"
	fi
fi

run_version "$version"
