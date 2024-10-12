#!/bin/sh

set -ue

AE_VERSION="0.0.1"
AE_USER_AGENT="ae $AE_VERSION"

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
	echo "  help        "
	echo "  self        "
	echo "  test        "
	echo "  prod        "
	echo "  schedule    "
	echo "  run         "
	echo "  renew       "
	echo
	echo "Environment variables:"
	echo "  "
}

main() {
	cmd=${1-""}
	case "$cmd" in
	"") help; return 1 ;;
	"help") help ;;
	"self") self ;;
	"test") test ;;
	"prod") prod ;;
	"schedule") schedule ;;
	"run") run ;;
	"renew") renew ;;
	*) return 1 ;;
	esac
}

self() {
	status=0

	_=$(cycle self) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	_=$(populate) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	_=$(reload) || status=$?
	if [ $status -ne 0 ]; then
		_=$(restart) || status=$?
	fi

	if [ $status -ne 0 ]; then
		return $status
	fi
}

test() {
	status=0

	_=$(cycle test) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	_=$(populate) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	reload
}

prod() {
	status=0

	_=$(cycle prod) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	_=$(populate) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	reload
}

schedule() {
	bin=$(realpath "$0")
	run="$AE_CRON	\"$bin\" run > /dev/stdout 2> /dev/stderr"

	table=$(crontab -l 2> /dev/null)
	if echo "$table" | grep -F "$run" > /dev/null 2>&1; then
		return
	fi

	(echo "$table"; echo "$run") | crontab -
}

run() {
	status=0
	rid=$(uuid)

	_=$(ping start "$rid")
	_=$(renew) || status=$?
	_=$(ping $status "$rid")

	return $status
}

renew() {
	status=0

	_=$(cycle renew) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	reload
}

#
# Private subocommands
#

cycle() {
	status=0

	ifs="$IFS"
	IFS=","

	for domain in $AE_DOMAINS; do
		code=0

		case "$1" in
		"self") _=$(openssl_self "$domain") || code=$? ;;
		"test") _=$(acme_test "$domain") || code=$? ;;
		"prod") _=$(acme_prod "$domain") || code=$? ;;
		"renew") _=$(acme_renew "$domain") || code=$? ;;
		esac

		if [ $code -ne 0 ]; then
			status=1
			continue
		fi
	done

	IFS="$ifs"

	if [ $status -ne 0 ]; then
		return $status
	fi
}

populate() {
	status=0

	id=$(nginx_id) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	ifs="$IFS"
	IFS=","

	for domain in $AE_DOMAINS; do
		code=0
		content=$(nginx_certificate_conf "$domain")
		file="$AE_NGINX_DIR/snippets/acme/$domain/certificate.conf"
		_=$(nginx_echo "$id" "$content" "$file") || code=$?
		if [ $code -ne 0 ]; then
			status=1
			continue
		fi
	done

	IFS="$ifs"

	content=$(nginx_acme_challenge_conf)
	file="$AE_NGINX_DIR/snippets/acme/acme_challenge.conf"
	_=$(nginx_echo "$id" "$content" "$file") || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	content=$(nginx_intermediate_conf)
	file="$AE_NGINX_DIR/snippets/acme/intermediate.conf"
	_=$(nginx_echo "$id" "$content" "$file") || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	content=$(nginx_redirect_conf)
	file="$AE_NGINX_DIR/snippets/acme/redirect.conf"
	_=$(nginx_echo "$id" "$content" "$file") || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	content=$(openssl_dhparam) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	file="$AE_NGINX_DIR/ssl/acme/$AE_DHPARAM_FILE"
	_=$(nginx_echo "$id" "$content" "$file") || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi
}

reload() {
	status=0

	id=$(nginx_id running) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	_=$(nginx_reload "$id") || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi
}

restart() {
	status=0

	id=$(nginx_id) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	_=$(nginx_restart "$id") || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi
}

ping() {
	status=0

	u="$AE_HEALTHCHECKS_URL"
	if [ -z "$u" ]; then
		return
	fi

	_=$(
		curl \
			--header "Accept: text/plain" \
			--header "User-Agent: $AE_USER_AGENT" \
			--max-time 10 \
			--request GET \
			--retry 5 \
			--silent \
			"$(url "$u" "$1")?rid=$2"
	) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi
}

#
# OpenSSL utilities
#

openssl_self() {
	status=0

	dir="$AE_ACME_DIR/$1"
	if [ ! -d "$dir" ]; then
		mkdir -p "$dir"
	fi

	_=$(
		openssl req \
			-days 1 \
			-keyout "$dir/$AE_PRIVKEY_FILE" \
			-newkey "rsa:$AE_KEY_SIZE" \
			-nodes \
			-out "$dir/$AE_FULLCHAIN_FILE" \
			-quiet \
			-subj "/CN=localhost" \
			-x509 \
			2>&1
	) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	cp "$dir/$AE_FULLCHAIN_FILE" "$dir/$AE_CHAIN_FILE"
}

openssl_dhparam() {
	status=0

	result=$(
		openssl dhparam \
			-quiet \
			"$AE_KEY_SIZE" \
			2>&1
	) || status=$?
	if [ $status -ne 0 ]; then
		echo "$result"
		return $status
	fi

	echo "$result"
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
	status=0

	_=$(
		acme \
			--days "$AE_DAYS" \
			--domain "$1" \
			--email "$AE_EMAIL" \
			--issue \
			--server "$AE_SERVER" \
			--webroot "$AE_WEBROOT_DIR/$1"
	) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	_=$(
		acme \
			--ca-file "$AE_ACME_DIR/$1/$AE_CHAIN_FILE" \
			--cert-file "$AE_ACME_DIR/$1/$AE_CERT_FILE" \
			--fullchain-file "$AE_ACME_DIR/$1/$AE_FULLCHAIN_FILE" \
			--install-cert \
			--key-file "$AE_ACME_DIR/$1/$AE_PRIVKEY_FILE" \
			--no-cron
	) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi
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
	status=0

	filters="{\"label\": [\"com.docker.compose.service=$AE_NGINX_SERVICE\"]"
	if [ "$1" = "running" ]; then
		filters="$filters, \"status\": [\"running\"]"
	fi
	filters="$filters}"

	response=$(docker_get containers/json "filters=$filters") || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	id=$(docker_id "$response")
	if [ -z "$id" ]; then
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
	status=0

	_=$(
		docker_post "containers/$1/exec" "{
			\"AttachStdin\": false,
			\"AttachStdout\": true,
			\"AttachStderr\": true,
			\"Tty\": false,
			\"Cmd\": $2
		}"
	) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi

	id=$(docker_id "$r")
	if [ -z "$id" ]; then
		return 1
	fi

	_=$(
		docker_post "exec/$id/start" '{
			"Detach": false,
			"Tty": false
		}'
	) || status=$?
	if [ $status -ne 0 ]; then
		return $status
	fi
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

uuid() {
	cat /proc/sys/kernel/random/uuid
}

url() {
	b="$1"
	case "$b" in
	*/) b="${b%/}" ;;
	esac
	echo "$b/$2"
}

log() {
	s="$1"

	case "$s" in
	INFO*)
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
