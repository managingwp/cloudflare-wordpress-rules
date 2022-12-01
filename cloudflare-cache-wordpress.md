# Don't cache wp-admin if logged in
* Action: Bypass Cache
* Expression: ```(http.request.uri.path in {"/wp-admin/*" "/wp-includes/*" "/wp-content/plugins/*"} and http.cookie contains "wordpress_logged")```