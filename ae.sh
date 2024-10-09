#!/bin/sh

set -ue

AE_CONFIG_DIR="/etc/acme"
AE_CONFIG_VOLUME="/etc/acme"
# AE_CRON=
AE_DAYS=30
AE_DOCKER_SOCKET="/var/run/docker.sock"
AE_DOCKER_URL="http://localhost/"
# AE_DOMAINS=
# AE_EMAIL=
# AE_PING_URL=
AE_SERVER="letsencrypt"
AE_TEST_SERVER="letsencrypt_test"
AE_WEBROOT_DIR="/var/www"

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
	echo "  AE_DOMAINS      A comma-separated list of domains"
}

main() {
	cmd=${1-""}
	case "$cmd" in
	"") help; return 1;;
	"help") help;;
	"self") self;;
	"test") test;;
	*) return 1;;
	esac
}

self() {
	log "INFO Generating a self-signed certificate"
	cmd_status=0

	cfg_dir="$AE_CONFIG_DIR"
	if [ ! -d "$cfg_dir" ]; then
		mkdir -p "$cfg_dir"
	fi

	ifs="$IFS"
	IFS=","

	for domain in $AE_DOMAINS; do
		status=0

		dom_dir="$cfg_dir/$domain"
		if [ -d "$dom_dir" ]; then
			cmd_status=1
			log "ERROR The certificate for the domain '$domain' already exists"
			continue
		fi

		log "INFO Generating a self-signed certificate for the domain '$domain'"

		mkdir "$dom_dir"

		_=$(
			openssl req \
				-days 1 \
				-keyout "$dom_dir/privkey.pem" \
				-newkey rsa:2048 \
				-nodes \
				-out "$dom_dir/fullchain.pem" \
				-quiet \
				-subj "/CN=localhost" \
				-x509
		) || status=$?

		if [ $status -ne 0 ]; then
			cmd_status=1
			log "ERROR The self-signed certificate for the domain '$domain' has not been generated"
			continue
		fi

		cp "$dom_dir/fullchain.pem" "$dom_dir/chain.pem"
	done

	IFS="$ifs"

	if [ $cmd_status -ne 0 ]; then
		log "ERROR The self-signed certificate has not been generated"
		return
	fi

	log "INFO The self-signed certificate has been generated"
	restart
}

test() {
	log "INFO Obtaining a test certificate"
	status=0

	# shellcheck disable=SC2046
	_=$(
		acme \
			--issue \
			--server "$AE_TEST_SERVER" \
			--test \
			$(options)
	) || status=$?

	if [ $status -ne 0 ]; then
		log "ERROR The test certificate has not been obtained"
		return $status
	fi

	log "INFO The test certificate has been obtained"
	reload
}

prod() {
	log "INFO Obtaining a production certificate"
	status=0

	# shellcheck disable=SC2046
	_=$(
		acme \
			--ca-file "$AE_CONFIG_DIR/chain.pem" \
			--cert-file "$AE_CONFIG_DIR/cert.pem" \
			--days "$AE_DAYS" \
			--email "$AE_EMAIL" \
			--fullchain-file "$AE_CONFIG_DIR/fullchain.pem" \
			--install-cert \
			--key-file "$AE_CONFIG_DIR/privkey.pem" \
			--no-cron \
			--server "$AE_SERVER" \
			$(options)
	) || status=$?

	if [ $status -ne 0 ]; then
		log "ERROR The production certificate has not been obtained"
		return $status
	fi

	log "INFO The production certificate has been obtained"
}

restart() {
	log "INFO Restarting the nginx container"
	status=0

	id=$(
		curl \
			--header "Content-Type: application/json" \
			--request GET \
			--silent \
			--unix-socket "$AE_DOCKER_SOCKET" \
			"${AE_DOCKER_URL}containers/json?all=true&filters=%7B%22volume%22%3A%5B%22$AE_CONFIG_VOLUME%22%5D%7D" | \
		grep -o '"Id":"[^"]*"' | \
		cut -d'"' -f4 | \
		grep -v "^$(hostname)" | \
		head -n 1
	)

	if [ -z "$id" ]; then
		log "ERROR The container has not been found"
		return 1
	fi

	_=$(
		curl \
			--header "Content-Type: application/json" \
			--request POST \
			--silent \
			--unix-socket "$AE_DOCKER_SOCKET" \
			"${AE_DOCKER_URL}containers/$id/restart"
	) || status=$?

	if [ $status -ne 0 ]; then
		log "ERROR The container has not been restarted"
		return $status
	fi

	log "INFO The container has been restarted"
}

reload() {
	log "INFO Reloading the nginx configuration"
	status=0

	id=$(
		curl \
			--header "Content-Type: application/json" \
			--request GET \
			--silent \
			--unix-socket "$AE_DOCKER_SOCKET" \
			"${AE_DOCKER_URL}containers/json?filters=%7B%22volume%22%3A%5B%22$AE_CONFIG_VOLUME%22%5D%7D" | \
		grep -o '"Id":"[^"]*"' | \
		cut -d'"' -f4 | \
		grep -v "^$(hostname)" | \
		head -n 1
	) || status=$?

	if [ $status -ne 0 ]; then
		log "ERROR The container has not been found"
		return $status
	fi

	if [ -z "$id" ]; then
		log "ERROR The container has not been found"
		return 1
	fi

	id=$(
		curl \
			--header "Content-Type: application/json" \
			--request POST \
			--silent \
			--unix-socket "$AE_DOCKER_SOCKET" \
			--data '{
				"AttachStdin": false,
				"AttachStdout": true,
				"AttachStderr": true,
				"Tty": false,
				"Cmd": ["nginx", "-s", "reload"]
			}' \
			"${AE_DOCKER_URL}containers/$id/exec" | \
		grep -o '"Id":"[^"]*"' | \
		cut -d'"' -f4
	) || status=$?

	if [ $status -ne 0 ]; then
		log "ERROR The nginx configuration has not been reloaded"
		return $status
	fi

	if [ -z "$id" ]; then
		log "ERROR The nginx configuration has not been reloaded"
		return 1
	fi

	_=$(
		curl \
			--data '{"Detach": false, "Tty": false}' \
			--header "Content-Type: application/json" \
			--output - \
			--request POST \
			--silent \
			--unix-socket /var/run/docker.sock \
			"${AE_DOCKER_URL}exec/$id/start"
	) || status=$?

	if [ $status -ne 0 ]; then
		log "ERROR The nginx configuration has not been reloaded"
		return $status
	fi

	log "INFO The nginx configuration has been reloaded"
}

options() {
	s=""

	ifs="$IFS"
	IFS=","

	for domain in $AE_DOMAINS; do
		s="${s} --domain ${domain}"
		s="${s} --webroot ${AE_WEBROOT_DIR}/${domain}"
	done

	IFS="$ifs"

	echo "$s"
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

main "$@"
