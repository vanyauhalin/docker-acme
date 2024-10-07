FROM vanyauhalin/nginx
ENV \
	LE_CONFIG_DIR=/etc/letsencrypt \
	LE_LOGS_DIR=/var/log/letsencrypt \
	LE_WEBROOT_DIR=/var/www \
	LE_WORK_DIR=/var/lib/letsencrypt
WORKDIR /srv
COPY entrypoint.sh /
COPY le.sh .
RUN \
	apk add --no-cache certbot openssl && \
	chmod +x /entrypoint.sh le.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
