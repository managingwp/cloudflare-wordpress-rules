#!/usr/bin/env bash

# ================================
# -- CF_PROTECT_WP $ZONE_ID
# ================================
function CF_PROTECT_WP () {
	local ZONE_ID=$1
	# -- Block xmlrpc.php - Priority 1
	_running2 "Creating - Block xml-rpc.php rule on $DOMAIN - $ZONE_ID"
	CF_CREATE_FILTER_ID=$(CF_CREATE_FILTER $ZONE_ID 'http.request.uri.path eq \"/xmlrpc.php\"')
	[[ $? == "1" ]] && exit 1
	CF_CREATE_RULE_ID=$(CF_CREATE_RULE $ZONE_ID $CF_CREATE_FILTER_ID "block" "1" "Block xml-rpc.php")
	[[ $? == "1" ]] && exit 1
	_success "Completed Block xml-rpc.php rule - $CF_CREATE_RULE_ID"

	_separator

	# -- Allow URI Query, URL, User Agents, and IPs (Allow) - Priority 2
	_running2 "  Creating - Allow URI Query, URL, User Agents, and IPs (Allow)"
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

	CF_CREATE_FILTER_ID=$(CF_CREATE_FILTER $ZONE_ID '(ip.src in { '"${BLOG_VAULT_IPS_B}"' }) or (ip.src in {'"${WP_UMBRELLA}"'})')
	[[ $? == "1" ]] && exit 1
	CF_CREATE_RULE_ID=$(CF_CREATE_RULE $ZONE_ID $CF_CREATE_FILTER_ID "allow" "2" "Allow URI Query, URL, User Agents, and IPs (Allow)")
	[[ $? == "1" ]] && exit 1
	_success "Completed  - Allow URI Query, URL, User Agents, and IPs (Allow)"
	_separator

	# --  Managed Challenge /wp-admin (Managed Challenge) - Priority 3
	_creating "  Creating Managed Challenge /wp-admin (Managed Challenge) rule"
	CF_CREATE_FILTER_ID=$(CF_CREATE_FILTER $ZONE_ID '(http.request.uri.path contains \"/wp-login.php\") or (http.request.uri.path contains \"/wp-admin/\" and http.request.uri.path ne \"/wp-admin/admin-ajax.php\" and not http.request.uri.path contains \"/wp-admin/js/password-strength-meter.min.js\")')
	[[ $? == "1" ]] && exit 1
	CF_CREATE_RULE_ID=$(CF_CREATE_RULE $ZONE_ID $CF_CREATE_FILTER_ID "managed_challenge" "3" "Managed Challenge /wp-admin (Managed Challenge)")
	[[ $? == "1" ]] && exit 1
	_success "Completed Managed Challenge /wp-admin (Managed Challenge)"
	_separator

	# --  Allow Good Bots and User Agent/URI/URL Query (Allow) - Priority 4
	_creating "  Allow Good Bots and User Agent/URI/URL Query (Allow)"
	CF_CREATE_FILTER_ID=$(CF_CREATE_FILTER $ZONE_ID '(cf.client.bot) or (http.user_agent contains \"Metorik API Client\") or (http.user_agent contains \"Wordfence Central API\") or (http.request.uri.query contains \"wc-api=wc_shipstation\") or (http.user_agent contains \"Better Uptime Bot\") or (http.user_agent contains \"ShortPixel\") or (http.user_agent contains \"WPUmbrella\")')
	[[ $? == "1" ]] && exit 1
	CF_CREATE_RULE_ID=$(CF_CREATE_RULE $ZONE_ID $CF_CREATE_FILTER_ID "allow" "4" "Allow Good Bots and User Agent/URI/URL Query (Allow)")
	[[ $? == "1" ]] && exit 1
	_success "Completed Allow Good Bots and User Agent/URI/URL Query (Allow)"
	_separator

    # -- Challenge Outside of GEO (JS Challenge)
    _creating "  Challenge Outside of GEO (JS Challenge)"
	CF_CREATE_FILTER_ID=$(CF_CREATE_FILTER $ZONE_ID '(not ip.geoip.country in {\"CA\" \"US\"})')
	[[ $? == "1" ]] && exit 1
	CF_CREATE_RULE_ID=$(CF_CREATE_RULE "$ZONE_ID" "$CF_CREATE_FILTER_ID" "js_challenge" "5" "Challenge Outside of GEO (JS Challenge)")
	[[ $? == "1" ]] && exit 1
	_success "Completed Challenge Outside of GEO (JS Challenge)"
    _separator

    _success "  Completed Protect WP profile"
}
