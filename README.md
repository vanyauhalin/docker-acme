<!-- generated 2024-10-10, Mozilla Guideline v5.7, nginx 1.26.0, OpenSSL 1.1.1w, intermediate configuration
https://ssl-config.mozilla.org/#server=nginx&version=1.26.0&config=intermediate&openssl=1.1.1w&guideline=5.7 -->

## File Structure

```txt
/etc
├─ acme
│  └─ example.com
│     ├─ chain.pem
│     ├─ fullchain.pem
│     └─ privkey.pem
└─ nginx
   ├─ snippets
   │  └─ acme
   │     ├─ example.com
   │     │  └─ certificate.conf
   │     ├─ acme-challenge.conf
   │     ├─ intermediate.conf
   │     └─ redirect.conf
   ├─ ssl
   │  └─ acme
   │     └─ dhparam.pem
   └─ nginx.conf
```

### Nginx Snippets

#### example.com/certificate.conf

```conf
ssl_certificate /etc/acme/example.com/fullchain.pem;
ssl_certificate_key /etc/acme/example.com/privkey.pem;
ssl_trusted_certificate /etc/acme/example.com/chain.pem;
```

#### acme-challenge.conf

```conf
location /.well-known/acme-challenge {
	root /var/www/$server_name;
}
```

#### intermediate.conf

```conf
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_dhparam /etc/nginx/ssl/acme/dhparam.pem;
ssl_prefer_server_ciphers off;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_session_cache shared:MozSSL:10m;
ssl_session_timeout 1d;
ssl_stapling on;
ssl_stapling_verify on;
```

#### redirect.conf

```conf
location / {
	return 301 https://$server_name$request_uri;
}
```

### Nginx Configuration

```conf
worker_processes auto;

events {}

http {
	include /etc/nginx/mime.types;

	server_tokens off;

	server {
		server_name example.com;
		listen 80;

		include /etc/nginx/snippets/acme/redirect.conf;
		include /etc/nginx/snippets/acme/acme-challenge.conf;
	}

	server {
		server_name example.com;
		listen 443 ssl;

		include /etc/nginx/snippets/acme/example.com/certificate.conf;
		include /etc/nginx/snippets/acme/intermediate.conf;

		location / {
			root /etc/nginx/html;
		}
	}
}
```
