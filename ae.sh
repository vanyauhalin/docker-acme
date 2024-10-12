#!/bin/sh

set -ue

AE_VERSION="0.0.1"
AE_USER_AGENT="me.vanyauhalin.docker-acme $AE_VERSION"

AE_CRON_STDOUT="/var/log/cron/output.log"
AE_CRON_STDERR="/var/log/cron/error.log"

: "${AE_CRON:="0	3	*	*	6"}"
: "${AE_DAYS:=30}"
: "${AE_DOMAINS:=""}"
: "${AE_EMAIL:=""}"
: "${AE_KEY_SIZE:=2048}"
: "${AE_SERVER:="letsencrypt"}"
: "${AE_TEST_SERVER:="letsencrypt_test"}"

: "${AE_ACME_DIR:="/etc/acme"}"
: "${AE_NGINX_DIR:="/etc/nginx"}"
: "${AE_WEBROOT_DIR:="/var/www"}"

: "${AE_CERT_FILE:="cert.pem"}"
: "${AE_CHAIN_FILE:="chain.pem"}"
: "${AE_DHPARAM_FILE:="dhparam.pem"}"
: "${AE_FULLCHAIN_FILE:="fullchain.pem"}"
: "${AE_PRIVKEY_FILE:="privkey.pem"}"

: "${AE_DOCKER_SOCKET:="/var/run/docker.sock"}"
: "${AE_DOCKER_URL:="http://localhost/"}"
: "${AE_HEALTHCHECKS_URL:=}"
: "${AE_NGINX_SERVICE:="nginx"}"

help() {
	echo "Usage: ae <subcommand>"
	echo
	echo "Subcommands:"
	echo "  help        Shows this help message"
	echo "  self        Obtains self-signed certificates"
	echo "  test        Obtains test certificates"
	echo "  prod        Obtains production certificates"
	echo "  schedule    Schedules certificate renewal"
	echo "  run         Runs scheduled operations"
	echo "  renew       Renews existing certificates"
	echo
	echo "Environment variables:"
	echo "  AE_CRON                Cron schedule for certificate renewal (computed: $AE_CRON)"
	echo "  AE_DAYS                Validity period for certificates when obtaining new ones (computed: $AE_DAYS)"
	echo "  AE_DOMAINS             Comma-separated list of domains to obtain certificates for (computed: $AE_DOMAINS)"
	echo "  AE_EMAIL               Email address to use when obtaining certificates (computed: $AE_EMAIL)"
	echo "  AE_KEY_SIZE            Size of the RSA key to be generated (computed: $AE_KEY_SIZE)"
	echo "  AE_SERVER              Server to use when obtaining production certificates (computed: $AE_SERVER)"
	echo "  AE_TEST_SERVER         Server to use when obtaining test certificates (computed: $AE_TEST_SERVER)"
	echo "  AE_ACME_DIR            Directory where certificates are stored (computed: $AE_ACME_DIR)"
	echo "  AE_NGINX_DIR           Directory where Nginx configuration is stored (computed: $AE_NGINX_DIR)"
	echo "  AE_WEBROOT_DIR         Directory where challenges are stored (computed: $AE_WEBROOT_DIR)"
	echo "  AE_CERT_FILE           Name of the certificate file (computed: $AE_CERT_FILE)"
	echo "  AE_CHAIN_FILE          Name of the chain file (computed: $AE_CHAIN_FILE)"
	echo "  AE_DHPARAM_FILE        Name of the DH parameters file (computed: $AE_DHPARAM_FILE)"
	echo "  AE_FULLCHAIN_FILE      Name of the full chain file (computed: $AE_FULLCHAIN_FILE)"
	echo "  AE_PRIVKEY_FILE        Name of the private key file (computed: $AE_PRIVKEY_FILE)"
	echo "  AE_DOCKER_SOCKET       Path to the Docker socket (computed: $AE_DOCKER_SOCKET)"
	echo "  AE_DOCKER_URL          URL to the Docker API (computed: $AE_DOCKER_URL)"
	echo "  AE_HEALTHCHECKS_URL    URL to Healthchecks API (computed: $AE_HEALTHCHECKS_URL)"
	echo "  AE_NGINX_SERVICE       Name of the Nginx service (computed: $AE_NGINX_SERVICE)"
}

main() {
	case "${1-""}" in
	"")
		help
		return 1
		;;
	"help")
		help
		;;
	"self")
		self
		;;
	"test")
		test
		;;
	"prod")
		prod
		;;
	"schedule")
		schedule
		;;
	"run")
		run
		;;
	"renew")
		renew
		;;
	*)
		return 1
		;;
	esac
}

self() {
	log "INFO Obtaining self-signed certificates"
	status=0

	result=$(cycle self 2>&1) || status=$?
	if [ $status -ne 0 ]; then
		log "ERROR Failed to obtain self-signed certificates with status '$status':\n$result"
		return $status
	fi

	result=$(populate 2>&1) || status=$?
	if [ $status -ne 0 ]; then
		log "ERROR Failed to populate Nginx configuration with status '$status':\n$result"
		return $status
	fi

	result=$(reload 2>&1) || status=$?
	if [ $status -ne 0 ]; then
		log "WARN Failed to reload Nginx with status '$status':\n$result"
		result=$(restart 2>&1) || status=$?
	fi

	if [ $status -ne 0 ]; then
		log "ERROR Failed to restart Nginx with status '$status':\n$result"
		return $status
	fi

	log "INFO Successfully obtained self-signed certificates"
}

test() {
	log "INFO Obtaining test certificates"
	status=0

	result=$(cycle test 2>&1) || status=$?
	if [ $status -ne 0 ]; then
		log "ERROR Failed to obtain test certificates with status '$status':\n$result"
		return $status
	fi

	result=$(populate 2>&1) || status=$?
	if [ $status -ne 0 ]; then
		log "ERROR Failed to populate Nginx configuration with status '$status':\n$result"
		return $status
	fi

	result=$(reload 2>&1) || status=$?
	if [ $status -ne 0 ]; then
		log "ERROR Failed to reload Nginx with status '$status':\n$result"
		return $status
	fi

	log "INFO Successfully obtained test certificates"
}

prod() {
	log "INFO Obtaining production certificates"
	status=0

	result=$(cycle prod 2>&1) || status=$?
	if [ $status -ne 0 ]; then
		log "ERROR Failed to obtain production certificates with status '$status':\n$result"
		return $status
	fi

	result=$(populate 2>&1) || status=$?
	if [ $status -ne 0 ]; then
		log "ERROR Failed to populate Nginx configuration with status '$status':\n$result"
		return $status
	fi

	result=$(reload 2>&1) || status=$?
	if [ $status -ne 0 ]; then
		log "ERROR Failed to reload Nginx with status '$status':\n$result"
		return $status
	fi

	log "INFO Successfully obtained production certificates"
}

schedule() {
	log "INFO Scheduling cron job for renewal"

	if ! pgrep -x crond > /dev/null 2>&1; then
		log "INFO Cron daemon is not running, starting it"
		crond
	fi

	bin=$(realpath "$0")
	cmd="$AE_CRON	\"$bin\" run >> \"$AE_CRON_STDOUT\" 2>> \"$AE_CRON_STDERR\""

	table=$(crontab -l 2> /dev/null)
	if echo "$table" | grep -F "$cmd" > /dev/null 2>&1; then
		log "INFO Renewal already scheduled"
		return
	fi

	(echo "$table"; echo "$cmd") | crontab -
	log "INFO Successfully scheduled renewal"
}

run() {
	log "INFO Running scheduled operations"
	status=0
	rid=$(uuid)

	_=$(ping start "$rid")
	_=$(renew) || status=$?
	_=$(ping $status "$rid")

	if [ $status -ne 0 ]; then
		log "ERROR Failed to run scheduled operations with status '$status'"
	else
		log "INFO Successfully ran scheduled operations"
	fi

	return $status
}

renew() {
	log "INFO Renewing certificates"
	status=0

	result=$(cycle renew 2>&1) || status=$?
	if [ $status -ne 0 ]; then
		log "ERROR Failed to renew certificates with status '$status':\n$result"
		return $status
	fi

	result=$(reload 2>&1) || status=$?
	if [ $status -ne 0 ]; then
		log "ERROR Failed to reload Nginx with status '$status':\n$result"
		return $status
	fi

	log "INFO Successfully renewed certificates"
}

#
# Private subcommands
#

cycle() {
	ifs="$IFS"
	IFS=","

	for domain in $AE_DOMAINS; do
		case "$1" in
		"self")
			openssl_self "$domain"
			;;
		"test")
			acme_test "$domain"
			;;
		"prod")
			acme_prod "$domain"
			;;
		"renew")
			acme_renew "$domain"
			;;
		esac
	done

	IFS="$ifs"
}

populate() {
	id=$(nginx_id)

	ifs="$IFS"
	IFS=","

	for domain in $AE_DOMAINS; do
		content=$(nginx_certificate_conf "$domain")
		file="$AE_NGINX_DIR/snippets/acme/$domain/certificate.conf"
		nginx_echo "$id" "$content" "$file"
	done

	IFS="$ifs"

	content=$(nginx_acme_challenge_conf)
	file="$AE_NGINX_DIR/snippets/acme/acme_challenge.conf"
	nginx_echo "$id" "$content" "$file"

	content=$(nginx_intermediate_conf)
	file="$AE_NGINX_DIR/snippets/acme/intermediate.conf"
	nginx_echo "$id" "$content" "$file"

	content=$(nginx_redirect_conf)
	file="$AE_NGINX_DIR/snippets/acme/redirect.conf"
	nginx_echo "$id" "$content" "$file"

	content=$(openssl_dhparam)
	file="$AE_NGINX_DIR/ssl/acme/$AE_DHPARAM_FILE"
	nginx_echo "$id" "$content" "$file"
}

reload() {
	id=$(nginx_id running)
	nginx_reload "$id"
}

restart() {
	id=$(nginx_id)
	nginx_restart "$id"
}

ping() {
	u="$AE_HEALTHCHECKS_URL"
	if [ -z "$u" ]; then
		return
	fi

	curl \
		--header "Accept: text/plain" \
		--header "User-Agent: $AE_USER_AGENT" \
		--max-time 10 \
		--request GET \
		--retry 5 \
		--silent \
		"$(url "$u" "$1")?rid=$2"
}

#
# OpenSSL utilities
#

openssl_self() {
	dir="$AE_ACME_DIR/$1"
	if [ ! -d "$dir" ]; then
		mkdir -p "$dir"
	fi

	openssl req \
		-days 1 \
		-keyout "$dir/$AE_PRIVKEY_FILE" \
		-newkey "rsa:$AE_KEY_SIZE" \
		-nodes \
		-out "$dir/$AE_FULLCHAIN_FILE" \
		-quiet \
		-subj "/CN=localhost" \
		-x509

	cp "$dir/$AE_FULLCHAIN_FILE" "$dir/$AE_CHAIN_FILE"
}

openssl_dhparam() {
	openssl dhparam -quiet "$AE_KEY_SIZE"
}

#
# acme.sh utilities
#

acme_test() {
	acme \
		--domain "$1" \
		--issue \
		--server "$AE_TEST_SERVER" \
		--test \
		--webroot "$AE_WEBROOT_DIR/$1"
}

acme_prod() {
	acme \
		--days "$AE_DAYS" \
		--domain "$1" \
		--email "$AE_EMAIL" \
		--issue \
		--server "$AE_SERVER" \
		--webroot "$AE_WEBROOT_DIR/$1"

	acme \
		--ca-file "$AE_ACME_DIR/$1/$AE_CHAIN_FILE" \
		--cert-file "$AE_ACME_DIR/$1/$AE_CERT_FILE" \
		--fullchain-file "$AE_ACME_DIR/$1/$AE_FULLCHAIN_FILE" \
		--install-cert \
		--key-file "$AE_ACME_DIR/$1/$AE_PRIVKEY_FILE" \
		--no-cron
}

acme_renew() {
	acme \
		--domain "$1" \
		--force \
		--renew
}

#
# Nginx utilities
#

nginx_id() {
	filters="{\"label\": [\"com.docker.compose.service=$AE_NGINX_SERVICE\"]"
	if [ "$1" = "running" ]; then
		filters="$filters, \"status\": [\"running\"]"
	fi
	filters="$filters}"

	result=$(docker_get containers/json "filters=$filters")

	id=$(docker_id "$result")
	if [ -z "$id" ]; then
		echo "No Nginx container found"
		return 1
	fi

	echo "$id"
}

nginx_echo() {
	docker_exec "$1" "[\"sh\", \"-c\", \"echo '$2' > '$3'\"]"
}

nginx_restart() {
	docker_post "containers/$1/restart"
}

nginx_reload() {
	docker_exec "$1" '["nginx", "-s", "reload"]'
}

nginx_certificate_conf() {
	echo "ssl_certificate $AE_ACME_DIR/$1/$AE_FULLCHAIN_FILE;"
	echo "ssl_certificate_key $AE_ACME_DIR/$1/$AE_PRIVKEY_FILE;"
	echo "ssl_trusted_certificate $AE_ACME_DIR/$1/$AE_CHAIN_FILE;"
}

nginx_acme_challenge_conf() {
	echo "location /.well-known/acme-challenge {"
	echo "	root $AE_WEBROOT_DIR/\$server_name;"
	echo "}"
}

nginx_intermediate_conf() {
	echo "ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;"
	echo "ssl_dhparam $AE_NGINX_DIR/ssl/acme/$AE_DHPARAM_FILE;"
	echo "ssl_prefer_server_ciphers off;"
	echo "ssl_protocols TLSv1.2 TLSv1.3;"
	echo "ssl_session_cache shared:MozSSL:10m;"
	echo "ssl_session_timeout 1d;"
	echo "ssl_stapling on;"
	echo "ssl_stapling_verify on;"
}

nginx_redirect_conf() {
	echo "location / {"
	echo "	return 301 https://\$server_name\$request_uri;"
	echo "}"
}

#
# Docker utilities
#

docker_exec() {
	result=$(
		docker_post "containers/$1/exec" "{
			\"AttachStdin\": false,
			\"AttachStdout\": true,
			\"AttachStderr\": true,
			\"Tty\": false,
			\"Cmd\": $2
		}"
	)

	id=$(docker_id "$result")
	if [ -z "$id" ]; then
		echo "No exec ID found"
		return 1
	fi

	docker_post "exec/$id/start" '{
		"Detach": false,
		"Tty": false
	}'
}

docker_get() {
	curl \
		--data-urlencode "$2" \
		--get \
		--header "Accept: application/json" \
		--header "User-Agent: $AE_USER_AGENT" \
		--request GET \
		--silent \
		--unix-socket "$AE_DOCKER_SOCKET" \
		"$(url "$AE_DOCKER_URL" "$1")"
}

docker_post() {
	curl \
		--data "$2" \
		--header "Accept: application/json" \
		--header "Content-Type: application/json" \
		--header "User-Agent: $AE_USER_AGENT" \
		--request POST \
		--silent \
		--unix-socket "$AE_DOCKER_SOCKET" \
		"$(url "$AE_DOCKER_URL" "$1")"
}

docker_id() {
	echo "$1" | grep -o '"Id":"[^"]*"' | cut -d'"' -f4
}

#
# General utilities
#

url() {
	b="$1"

	case "$b" in
	*/)
		b="${b%/}"
		;;
	esac

	echo "$b/$2"
}

uuid() {
	cat /proc/sys/kernel/random/uuid
}

log() {
	s="$1"

	case "$s" in
	INFO*|WARN*)
		p=$(echo "$s" | cut -d" " -f1)
		r=$(echo "$s" | cut -d" " -f2-)
		s="$p  $r"
		;;
	esac

	printf "%b" "$(date +'%Y-%m-%d %H:%M:%S') $s\n"
}

#
# Entry point
#

main "$@"
