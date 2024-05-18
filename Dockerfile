ARG CERTBOT_VERSION=2.10.0
FROM vanyauhalin/nginx
ARG CERTBOT_VERSION
ENV \
	LE_CONFIG_DIR=/etc/letsencrypt \
	LE_LOGS_DIR=/var/log/letsencrypt \
	LE_WEBROOT_DIR=/var/www \
	LE_WORK_DIR=/var/lib/letsencrypt
WORKDIR /srv
COPY entrypoint.sh /
COPY le.sh .
RUN set -e && \
	apk add --no-cache certbot openssl && \
	chmod +x /entrypoint.sh && \
	chmod +x le.sh && \
	mkdir /etc/nginx/snippets && \
	cd /etc/nginx/snippets && \
		wget --output-document=options-ssl-nginx.conf "https://raw.githubusercontent.com/certbot/certbot/v$CERTBOT_VERSION/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf" && \
		wget --output-document=ssl-dhparams.pem "https://raw.githubusercontent.com/certbot/certbot/v$CERTBOT_VERSION/certbot/certbot/ssl-dhparams.pem"
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
