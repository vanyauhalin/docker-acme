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

## Example Configuration

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
