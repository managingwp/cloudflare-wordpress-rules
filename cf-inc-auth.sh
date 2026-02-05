#!/bin/bash
# ==================================================
# Cloudflare Authentication Library v2.0
# Supports profile-based credentials and interactive selection
# ==================================================

# Global variables for authentication
declare -g CF_AUTH_ACCOUNT=""
declare -g CF_AUTH_TOKEN=""
declare -g CF_AUTH_KEY=""
declare -g CF_AUTH_PROFILE=""
declare -g CF_AUTH_METHOD=""
declare -gA _profile_selection_map=()
declare -g _PROFILE_SELECTION_COUNT=0

# ==================================================
# Load .cloudflare configuration file
# ==================================================
function _cf_load_config() {
    local config_file="${1:-$HOME/.cloudflare}"
    
    if [[ ! -f "$config_file" ]]; then
        _error "Configuration file $config_file not found"
        return 1
    fi
    
    # Source the config file safely
    # Strips inline comments so values like "CF_KEY=abc # note" load as "abc".
    while IFS= read -r line; do
        # Trim leading/trailing whitespace
        line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        # Skip comments and empty lines
        [[ $line =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Remove inline comments (anything after an unescaped #)
        line=$(echo "$line" | sed 's/[[:space:]]*#.*$//')
        # Trim again in case whitespace remains after stripping comment
        line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [[ -z "$line" ]] && continue

        # Split key and value
        local key value
        key=${line%%=*}
        value=${line#*=}

        # Skip lines without '='
        [[ "$key" == "$line" ]] && continue

        # Clean key and value
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | sed 's/^["'"'']*//;s/["'"'']*$//' | xargs)
        
        # Export the variable
        export "$key"="$value"
    done < "$config_file"
}

# ==================================================
# Detect available authentication profiles
# ==================================================
function _cf_detect_profiles() {
    local config_file="${1:-$HOME/.cloudflare}"
    local -a profiles=()
    local profile_pattern="^CF_(ACCOUNT|TOKEN|KEY)_([A-Z0-9_]+)$"
    
    # Get all CF_ variables from the config file and extract profile names
    while IFS='=' read -r var value; do
        # Skip comments and empty lines
        [[ $var =~ ^[[:space:]]*# ]] && continue
        [[ -z "$var" ]] && continue
        
        # Clean up the var name
        var=$(echo "$var" | xargs)
        
        if [[ $var =~ $profile_pattern ]]; then
            local profile="${BASH_REMATCH[2]}"
            # Skip generic CF_ variables
            [[ "$profile" =~ ^(ACCOUNT|TOKEN|KEY)$ ]] && continue
            
            # Add to profiles array if not already present
            if [[ ! " ${profiles[*]} " =~ \ ${profile}\  ]]; then
                profiles+=("$profile")
            fi
        fi
    done < "$config_file"
    
    # Also check for generic credentials (CF_ACCOUNT, CF_KEY, CF_TOKEN)
    local has_generic=0
    while IFS='=' read -r var value; do
        # Skip comments and empty lines
        [[ $var =~ ^[[:space:]]*# ]] && continue
        [[ -z "$var" ]] && continue
        
        # Clean up the var name
        var=$(echo "$var" | xargs)
        
        if [[ "$var" == "CF_ACCOUNT" || "$var" == "CF_KEY" || "$var" == "CF_TOKEN" ]]; then
            has_generic=1
            break
        fi
    done < "$config_file"
    
    if [[ $has_generic -eq 1 ]]; then
        profiles+=("DEFAULT")
    fi
    
    printf '%s\n' "${profiles[@]}"
}

# ==================================================
# Get credentials for a specific profile
# ==================================================
function _cf_get_profile_creds() {
    local profile="$1"
    local config_file="${2:-$HOME/.cloudflare}"
    local -A creds=()
    
    # Read from config file
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ $line =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Remove inline comments and trim
        line=$(echo "$line" | sed 's/[[:space:]]*#.*$//')
        [[ -z "$line" ]] && continue

        # Split key and value on first '='
        var=${line%%=*}
        value=${line#*=}
        [[ "$var" == "$line" ]] && continue

        # Clean up var name
        var=$(echo "$var" | xargs)
        # Clean up value (strip surrounding quotes and whitespace)
        value=$(echo "$value" | sed 's/^["'\'']*//;s/["'\'']*$//' | xargs)
        
        if [[ "$profile" == "DEFAULT" ]]; then
            if [[ "$var" == "CF_ACCOUNT" ]]; then
                creds[account]="$value"
            elif [[ "$var" == "CF_TOKEN" ]]; then
                creds[token]="$value"
            elif [[ "$var" == "CF_KEY" ]]; then
                creds[key]="$value"
            fi
        else
            if [[ "$var" == "CF_ACCOUNT_${profile}" ]]; then
                creds[account]="$value"
            elif [[ "$var" == "CF_TOKEN_${profile}" ]]; then
                creds[token]="$value"
            elif [[ "$var" == "CF_KEY_${profile}" ]]; then
                creds[key]="$value"
            fi
        fi
    done < "$config_file"
    
    # Output in format: account|token|key
    printf '%s|%s|%s\n' "${creds[account]}" "${creds[token]}" "${creds[key]}"
}

# ==================================================
# Validate credentials
# ==================================================
function _cf_validate_creds() {
    local account="$1"
    local token="$2"
    local key="$3"
    
    # Must have either token OR (account + key)
    if [[ -n "$token" ]]; then
        [[ -z "$account" ]] && return 0  # Token-only auth is valid
        return 0
    elif [[ -n "$account" && -n "$key" ]]; then
        return 0
    else
        return 1
    fi
}

# ==================================================
# Format and display profiles (shared by list and select)
# ==================================================
function _cf_display_profiles_formatted() {
    local config_file="$1"
    local mode="$2"  # "list" or "select"
    local -a profiles
    local -a default_profiles
    local -a other_profiles
    mapfile -t profiles < <(_cf_detect_profiles "$config_file")
    
    if [[ ${#profiles[@]} -eq 0 ]]; then
        return 1
    fi
    
    # Separate DEFAULT profiles from others (DEFAULT goes first)
    for profile in "${profiles[@]}"; do
        if [[ "$profile" == "DEFAULT" ]]; then
            default_profiles+=("$profile")
        else
            other_profiles+=("$profile")
        fi
    done
    
    # Combine arrays with DEFAULT first
    local -a sorted_profiles=("${default_profiles[@]}" "${other_profiles[@]}")
    
    # Display header
    local redirect=""
    [[ "$mode" == "select" ]] && redirect=" >&2"
    
    if [[ "$mode" == "select" ]]; then
        echo "Multiple Cloudflare profiles found in $config_file:" >&2
        echo "" >&2
    else
        echo "Multiple Cloudflare profiles found in $config_file:"
        echo ""
    fi
    
    local counter=1
    # Use the global selection map (already declared at top level)
    # Just clear it and repopulate
    for i in "${!_profile_selection_map[@]}"; do unset '_profile_selection_map[$i]'; done
    
    for profile in "${sorted_profiles[@]}"; do
        local creds
        IFS='|' read -r account token key <<< "$(_cf_get_profile_creds "$profile" "$config_file")"
        
        local label="$profile"
        if [[ "$profile" == "DEFAULT" ]]; then
            label="Default"
        fi
        
        # Display and map Account API entries
        if [[ -n "$account" && -n "$key" ]]; then
            if [[ "$mode" == "select" ]]; then
                printf "%d. %s - Account API (%s)\n" "$counter" "$label" "$account" >&2
            else
                printf "%d. %s - Account API (%s)\n" "$counter" "$label" "$account"
            fi
            _profile_selection_map[$counter]="$profile"
            ((counter++))
        fi
        
        # Display and map Token API entries
        if [[ -n "$token" ]]; then
            if [[ "$mode" == "select" ]]; then
                printf "%d. %s - Token API\n" "$counter" "$label" >&2
            else
                printf "%d. %s - Token API\n" "$counter" "$label"
            fi
            _profile_selection_map[$counter]="$profile"
            ((counter++))
        fi
    done
    
    if [[ "$mode" == "select" ]]; then
        echo "" >&2
    else
        echo ""
    fi
    
    # Store the total count in global variable for caller to use
    _PROFILE_SELECTION_COUNT=$((counter - 1))
}

# ==================================================
# Interactive profile selection
# ==================================================
function _cf_select_profile() {
    local config_file="${1:-$HOME/.cloudflare}"
    local -a profiles
    mapfile -t profiles < <(_cf_detect_profiles "$config_file")
    
    if [[ ${#profiles[@]} -eq 0 ]]; then
        _error "No Cloudflare credentials found in $config_file"
        return 1
    fi
    
    if [[ ${#profiles[@]} -eq 1 ]]; then
        echo "${profiles[0]}"
        return 0
    fi
    
    # Display profiles and get total count
    # The function will populate _PROFILE_SELECTION_COUNT and _profile_selection_map
    _cf_display_profiles_formatted "$config_file" "select"
    local total_entries=$_PROFILE_SELECTION_COUNT
    
    while true; do
        read -p "Select a profile (1-$total_entries): " selection >&2
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 && $selection -le $total_entries ]]; then
            echo "${_profile_selection_map[$selection]}"
            return 0
        else
            echo "Invalid selection. Please choose 1-$total_entries" >&2
        fi
    done
}

# ==================================================
# Initialize Cloudflare authentication
# Usage: cf_auth_init [profile_name]
# ==================================================
function cf_auth_init() {
    local requested_profile="$1"
    local config_file="${2:-$HOME/.cloudflare}"
    
    _debug "Initializing Cloudflare authentication"
    
    # Load configuration
    if ! _cf_load_config "$config_file"; then
        return 1
    fi
    
    local profile=""
    
    # Determine which profile to use
    if [[ -n "$requested_profile" ]]; then
        # Specific profile requested
        profile="$requested_profile"
        _debug "Using requested profile: $profile"
    else
        # Auto-detect or select profile
        profile=$(_cf_select_profile "$config_file")
        if [[ $? -ne 0 ]]; then
            return 1
        fi
        _debug "Selected profile: $profile"
    fi
    
    # Get credentials for selected profile
    local creds
    IFS='|' read -r account token key <<< "$(_cf_get_profile_creds "$profile" "$config_file")"
    
    # Validate credentials
    if ! _cf_validate_creds "$account" "$token" "$key"; then
        _error "Invalid credentials for profile: $profile"
        return 1
    fi
    
    # Set global variables
    CF_AUTH_ACCOUNT="$account"
    CF_AUTH_TOKEN="$token"
    CF_AUTH_KEY="$key"
    CF_AUTH_PROFILE="$profile"
    
    # ==================================================
    # Backwards compatibility - Set legacy variables
    # ==================================================
    export API_ACCOUNT="$account"
    export API_TOKEN="$token"
    export API_APIKEY="$key"
    
    # Determine authentication method
    if [[ -n "$token" ]]; then
        CF_AUTH_METHOD="token"
        _success "Authenticated using token (profile: $profile)"
        _debug "Set API_TOKEN for backwards compatibility"
    else
        CF_AUTH_METHOD="key"
        _success "Authenticated using account/key (profile: $profile, account: $account)"
        _debug "Set API_ACCOUNT and API_APIKEY for backwards compatibility"
    fi
    
    return 0
}

# ==================================================
# Get authentication headers for API calls
# ==================================================
function cf_auth_headers() {
    if [[ "$CF_AUTH_METHOD" == "token" ]]; then
        echo "Authorization: Bearer $CF_AUTH_TOKEN"
    else
        echo "X-Auth-Email: $CF_AUTH_ACCOUNT"
        echo "X-Auth-Key: $CF_AUTH_KEY"
    fi
}

# ==================================================
# List available profiles
# ==================================================
function cf_auth_list_profiles() {
    local config_file="${1:-$HOME/.cloudflare}"
    
    # Use the shared display function
    _cf_display_profiles_formatted "$config_file" "list"
}

# ==================================================
# Backwards compatibility functions
# ==================================================
function cf_get_account() {
    echo "$CF_AUTH_ACCOUNT"
}

function cf_get_token() {
    echo "$CF_AUTH_TOKEN"
}

function cf_get_key() {
    echo "$CF_AUTH_KEY"
}

function cf_get_profile() {
    echo "$CF_AUTH_PROFILE"
}