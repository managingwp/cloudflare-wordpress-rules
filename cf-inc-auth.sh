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

# ==================================================
# Load .cloudflare configuration file
# ==================================================
function _cf_load_config() {
    local config_file="$HOME/.cloudflare"
    
    if [[ ! -f "$config_file" ]]; then
        _error "Configuration file $config_file not found"
        return 1
    fi
    
    # Source the config file safely
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Remove quotes and whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | sed 's/^["'\'']*//;s/["'\'']*$//' | xargs)
        
        # Export the variable
        export "$key"="$value"
    done < "$config_file"
}

# ==================================================
# Detect available authentication profiles
# ==================================================
function _cf_detect_profiles() {
    local -a profiles=()
    local profile_pattern="^CF_([A-Z0-9_]+)_(ACCOUNT|TOKEN|KEY)$"
    
    # Get all CF_ variables and extract profile names
    while IFS='=' read -r var value; do
        if [[ $var =~ $profile_pattern ]]; then
            local profile="${BASH_REMATCH[1]}"
            # Skip generic CF_ variables
            [[ "$profile" =~ ^(ACCOUNT|TOKEN|KEY)$ ]] && continue
            
            # Add to profiles array if not already present
            if [[ ! " ${profiles[*]} " =~ \ ${profile}\  ]]; then
                profiles+=("$profile")
            fi
        fi
    done < <(env | grep "^CF_")
    
    # Also check for generic credentials
    if [[ -n "${CF_ACCOUNT:-}" && -n "${CF_KEY:-}" ]] || [[ -n "${CF_TOKEN:-}" ]]; then
        profiles+=("DEFAULT")
    fi
    
    printf '%s\n' "${profiles[@]}"
}

# ==================================================
# Get credentials for a specific profile
# ==================================================
function _cf_get_profile_creds() {
    local profile="$1"
    local -A creds=()
    
    if [[ "$profile" == "DEFAULT" ]]; then
        creds[account]="${CF_ACCOUNT:-}"
        creds[token]="${CF_TOKEN:-}"
        creds[key]="${CF_KEY:-}"
    else
        local account_var="CF_${profile}_ACCOUNT"
        local token_var="CF_${profile}_TOKEN"
        local key_var="CF_${profile}_KEY"
        
        creds[account]="${!account_var:-}"
        creds[token]="${!token_var:-}"
        creds[key]="${!key_var:-}"
    fi
    
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
# Interactive profile selection
# ==================================================
function _cf_select_profile() {
    local -a profiles
    mapfile -t profiles < <(_cf_detect_profiles)
    
    if [[ ${#profiles[@]} -eq 0 ]]; then
        _error "No Cloudflare credentials found in $HOME/.cloudflare"
        return 1
    fi
    
    if [[ ${#profiles[@]} -eq 1 ]]; then
        echo "${profiles[0]}"
        return 0
    fi
    
    # Multiple profiles available - show selection menu
    echo "Multiple Cloudflare credential profiles found:" >&2
    echo "" >&2
    
    local i=1
    for profile in "${profiles[@]}"; do
        local creds
        IFS='|' read -r account token key <<< "$(_cf_get_profile_creds "$profile")"
        
        echo "  $i) $profile" >&2
        if [[ "$profile" == "DEFAULT" ]]; then
            echo "     Generic credentials" >&2
        fi
        
        if [[ -n "$token" ]]; then
            echo "     Token: ${token:0:8}..." >&2
        elif [[ -n "$account" && -n "$key" ]]; then
            echo "     Account: $account" >&2
            echo "     Key: ${key:0:8}..." >&2
        fi
        echo "" >&2
        ((i++))
    done
    
    while true; do
        read -p "Select profile (1-${#profiles[@]}): " selection >&2
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 && $selection -le ${#profiles[@]} ]]; then
            echo "${profiles[$((selection-1))]}"
            return 0
        else
            echo "Invalid selection. Please choose 1-${#profiles[@]}" >&2
        fi
    done
}

# ==================================================
# Initialize Cloudflare authentication
# Usage: cf_auth_init [profile_name]
# ==================================================
function cf_auth_init() {
    local requested_profile="$1"
    
    _debug "Initializing Cloudflare authentication"
    
    # Load configuration
    if ! _cf_load_config; then
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
        profile=$(_cf_select_profile)
        if [[ $? -ne 0 ]]; then
            return 1
        fi
        _debug "Selected profile: $profile"
    fi
    
    # Get credentials for selected profile
    local creds
    IFS='|' read -r account token key <<< "$(_cf_get_profile_creds "$profile")"
    
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
    local -a profiles
    mapfile -t profiles < <(_cf_detect_profiles)
    
    if [[ ${#profiles[@]} -eq 0 ]]; then
        echo "No Cloudflare credential profiles found"
        return 1
    fi
    
    echo "Available Cloudflare credential profiles:"
    echo ""
    
    for profile in "${profiles[@]}"; do
        local creds
        IFS='|' read -r account token key <<< "$(_cf_get_profile_creds "$profile")"
        
        printf "  %-15s" "$profile"
        if [[ -n "$token" ]]; then
            echo "Token: ${token:0:8}..."
        elif [[ -n "$account" && -n "$key" ]]; then
            echo "Account: $account"
        fi
    done
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