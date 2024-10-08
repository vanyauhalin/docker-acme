#!/bin/sh

set -ue

# AE_DOMAINS
# AE_EMAIL
AE_CONFIG_DIR="/etc/acme"
AE_WEBROOT_DIR="/var/www/"

help() {
	echo "Usage: ae <subcommand>"
	echo
	echo "Subcommands:"
	echo "  help      Show this help message"
	echo "  self      Generate a self-signed certificate"
	echo "  test      Obtain a test certificate"
	echo "  prod      Obtain a production certificate"
	echo "  renew     Renew the certificate"
	echo "  schedule  Schedule a job to renew the certificate"
	echo "  run       Run the job to renew the certificate"
}

main() {
	cmd=${1-""}
	case "$cmd" in
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
	*)
		return 1
		;;
	esac
}

self() {
	log "INFO Generating a self-signed certificate"

	cfg_dir="$AE_CONFIG_DIR"
	if [ ! -d "$cfg_dir" ]; then
		mkdir -p "$cfg_dir"
	fi

	ifs="$IFS"
	IFS=","

	for domain in $AE_DOMAINS; do
		dom_dir="$cfg_dir/$domain"
		if [ -d "$dom_dir" ]; then
			log "ERROR The certificate for the domain '$domain' already exists"
			return 1
		fi

		log "INFO Generating a self-signed certificate for the domain '$domain'"

		mkdir "$dom_dir"

		openssl req \
			-days 1 \
			-keyout "$dom_dir/privkey.pem" \
			-newkey rsa:2048 \
			-out "$dom_dir/fullchain.pem" \
			-subj "/CN=localhost" \
			-nodes \
			-x509 \
			> /dev/null 2>&1
		cp "$dom_dir/fullchain.pem" "$dom_dir/chain.pem"

		# file="$dom_dir/chain.pem"
		# chgrp nginx "$file"
		# chmod 644 "$file"

		# file="$dom_dir/fullchain.pem"
		# chgrp nginx "$file"
		# chmod 644 "$file"

		# file="$dom_dir/privkey.pem"
		# chgrp nginx "$file"
		# chmod 640 "$file"
	done

	IFS="$ifs"

	log "INFO The self-signed certificate has been generated"
}

test() {
	log "Obtaining a test certificate"
	# shellcheck disable=SC2046
	acme --issue --staging $(domains)
	log "The test certificate has been obtained"
}

# --install --no-cron --email

domains() {
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
		p=$(echo "$s" | cut -d=" " -f=1)
		r=$(echo "$s" | cut -d=" " -f=2-)
		s="$p $r"
		;;
	esac

	printf "%b" "$(date +'%Y/%m/%d %H:%M:%S') $s\n"
}

main "$@"
