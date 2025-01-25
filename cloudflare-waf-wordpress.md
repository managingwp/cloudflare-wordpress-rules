# Rules 12-16-2024 V2
## R1V2 - Block URI Query, URL, User Agents, and IPs (Block)
* Action: Block 
```
(http.request.uri.path eq "/wp-content/uploads/wp-activity-log/non_mirrored_logs.json") or (http.request.uri.path eq "/xmlrpc.php")
```

## R2V2 -  Allow URI Query, URL, User Agents, and IPs (Allow)
* Action: Skip
* WAF components to skip
  * All remaining custom rules
  * All rate limiting rules
  * All managed rules
  * All Super Bot Fight Mode Rules
```
(ip.src in {88.99.145.111 88.99.145.112 195.201.197.31 136.243.130.174 144.76.236.242 136.243.130.52 116.202.131.150 116.202.233.15 116.202.193.3 168.119.2.157 49.12.124.233 88.99.146.248 139.180.140.55 104.248.114.9 192.81.221.63 45.63.10.187 45.76.137.73 45.76.183.23 159.223.99.132 198.211.127.63 45.76.126.238 159.223.105.100 161.35.121.79 208.68.38.165 147.182.131.77 174.138.35.170 149.28.228.237 45.77.106.232 140.82.15.60 108.61.142.158 45.77.220.240 67.205.160.142 137.184.156.126 157.245.142.130 159.223.127.73 198.211.127.43 198.211.123.140 82.196.0.67 188.166.158.7 46.101.79.124 192.248.168.22 78.141.225.57 95.179.214.63 104.238.190.161 95.179.208.185 95.179.220.182 66.135.5.151 45.32.7.254 149.28.227.238 8.9.37.67 149.28.231.28 142.132.211.19 142.132.211.18 142.132.211.17 159.223.166.150 167.172.146.73 143.198.184.39 161.35.123.156 147.182.139.65 198.211.125.219 185.14.187.177 192.81.222.35 209.97.131.196 209.97.135.165 104.238.170.64 78.141.244.3 217.69.0.229 45.63.115.86 108.61.123.152 45.32.144.195 140.82.12.121 45.77.99.218 45.63.11.48 149.28.45.216 209.222.10.118 147.182.130.252 149.28.62.18 207.246.127.103 157.245.137.38 207.246.120.94 157.245.128.151 45.77.148.172 142.93.11.155 144.202.2.38 104.248.238.131 45.77.148.172 141.95.192.2 176.9.40.54 176.9.106.100 176.9.21.94}) 
or (http.request.uri.query contains "bvVersion") 
or (http.request.uri.query contains "wc-api=wc_shipstation") 
or (http.user_agent contains "Zapier") 
or (http.user_agent contains "Metorik API Client") 
or (http.user_agent contains "Wordfence Central API") 
or (http.user_agent eq "Better Uptime Bot") 
or (http.user_agent eq "ShortPixel") 
or (http.user_agent contains "WPUmbrella") 
or (http.user_agent contains "Integrately") 
or (http.user_agent contains "Uptime-Kuma") 
or (http.user_agent contains "Let's Encrypt") 
or (cf.client.bot)
```

## R3V2 – Managed Challenge /wp-admin (Managed Challenge)
* Action: Managed Challenge
```
(http.request.uri.path contains "/wp-login.php") or (http.request.uri.path contains "/wp-admin/" and http.request.uri.path ne "/wp-admin/admin-ajax.php" and not http.request.uri.path contains "/wp-admin/js/password-strength-meter.min.js")
```

## R4V2 – Challenge Outside of GEO (JS Challenge)
* Action: JS Challenge
```
(not ip.geoip.country in {"CA" "US"})
```