#!/bin/sh

set -ue

help() {
	echo "Usage: le.sh <subcommand>"
	echo
	echo "Subcommands:"
	echo "  help      Show this help message"
	echo "  dirs      Create the letsencrypt directories"
	echo "  self      Generate a self-signed certificate"
	echo "  unself    Remove the self-signed certificate"
	echo "  test      Obtain a test certificate"
	echo "  prod      Obtain a production certificate"
	echo "  renew     Renew the certificate"
	echo "  schedule  Schedule a job to renew the certificate"
	echo "  job       Run the job to renew the certificate"
	echo
	echo "Variables:"
	echo "  HC_URL          The healthchecks.io ping URL"
	echo "  LE_CONFIG_DIR   The letsencrypt configuration directory"
	echo "  LE_CRON         The cron expression to renew the certificate"
	echo "  LE_DOMAINS      The comma-separated list of domains"
	echo "  LE_EMAIL        The email address"
	echo "  LE_LOGS_DIR     The letsencrypt logs directory"
	echo "  LE_WEBROOT_DIR  The letsencrypt webroot directory"
	echo "  LE_WORK_DIR     The letsencrypt work directory"
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
	"dirs")
		# shellcheck disable=SC3044
		dirs
		;;
	"self")
		self
		;;
	"unself")
		unself
		;;
	"test")
		test
		;;
	"prod")
		prod
		;;
	"renew")
		renew
		;;
	"schedule")
		schedule
		;;
	"job")
		job
		;;
	*)
		log "Unknown the command '$1'"
		return 1
		;;
	esac
}

dirs() {
	log "Creating the letsencrypt directories"

	mkdir -p \
		"$LE_CONFIG_DIR" \
		"$LE_LOGS_DIR" \
		"$LE_WEBROOT_DIR" \
		"$LE_WORK_DIR"

	mkdir -p \
		"$LE_CONFIG_DIR/live" \
		"$(dirname "$(realpath "$0")")/self"

	ifs="$IFS"
	IFS=","

	for domain in $LE_DOMAINS; do
		dir="${LE_WEBROOT_DIR}/${domain}"
		mkdir -p "$dir"
	done

	IFS="$ifs"
}

self() {
	log "Generating a self-signed certificate"

	live_dir="$LE_CONFIG_DIR/live"
	if [ ! -d "$live_dir" ]; then
		log "The '$live_dir' directory does not exist"
		return 1
	fi

	self_dir="$(dirname "$(realpath "$0")")/self"
	if [ ! -d "$self_dir" ]; then
		log "The '$self_dir' directory does not exist"
		return 1
	fi

	ifs="$IFS"
	IFS=","

	for domain in $LE_DOMAINS; do
		live="$live_dir/$domain"
		if [ -d "$live" ]; then
			log "The certificate for the domain '$domain' already exists"
			continue
		fi

		self="$self_dir/$domain"
		if [ -d "$self" ]; then
			log "The self-signed certificate for the domain '$domain' already exists"
			continue
		fi

		log "Generating a self-signed certificate for the domain '$domain'"

		mkdir "$live" "$self"

		openssl req \
			-days 1 \
			-keyout "$self/privkey.pem" \
			-newkey rsa:1024 \
			-out "$self/fullchain.pem" \
			-subj "/CN=localhost" \
			-nodes \
			-x509 \
			> /dev/null 2>&1
		cp "$self/fullchain.pem" "$self/chain.pem"

		file="$self/chain.pem"
		chgrp nginx "$file"
		chmod 644 "$file"

		file="$self/fullchain.pem"
		chgrp nginx "$file"
		chmod 644 "$file"

		file="$self/privkey.pem"
		chgrp nginx "$file"
		chmod 640 "$file"

		for base in "chain.pem" "fullchain.pem" "privkey.pem"; do
			ln -s "$self/$base" "$live/$base"
			chmod 777 "$live/$base"
		done
	done

	IFS="$ifs"

	log "The self-signed certificate has been generated"
}

unself() {
	log "Removing the self-signed certificate"

	live_dir="$LE_CONFIG_DIR/live"
	if [ ! -d "$live_dir" ]; then
		log "The '$live_dir' directory does not exist"
		return 1
	fi

	self_dir="$(dirname "$(realpath "$0")")/self"
	if [ ! -d "$self_dir" ]; then
		log "The '$self_dir' directory does not exist"
		return 1
	fi

	ifs="$IFS"
	IFS=","

	for domain in $LE_DOMAINS; do
		live="$live_dir/$domain"
		if [ ! -d "$live" ]; then
			log "The certificate for the domain '$domain' does not exist"
			continue
		fi

		self="$self_dir/$domain"
		if [ ! -d "$self" ]; then
			log "The self-signed certificate for the domain '$domain' does not exist"
			continue
		fi

		log "Removing the self-signed certificate for the domain '$domain'"

		for base in "chain.pem" "fullchain.pem" "privkey.pem"; do
			link="$live/$base"
			traget=$(realpath "$link")
			rm "$link" "$traget"
		done

		rmdir "$live" "$self"
	done

	IFS="$ifs"

	log "The self-signed certificate has been removed"
}

test() {
	log "Obtaining a test certificate"
	# shellcheck disable=SC2046
	certbot certonly --staging $(options)
	reown
	nginx -s reload
	log "The test certificate has been obtained"
}

prod() {
	log "Obtaining a production certificate"
	# shellcheck disable=SC2046
	certbot certonly $(options)
	reown
	nginx -s reload
	log "The production certificate has been obtained"
}

renew() {
	log "Renewing the certificate"
	certbot renew --non-interactive
	reown
	nginx -s reload
	log "The certificate has been renewed"
}

options() {
	s="--agree-tos"
	s="${s} --no-eff-email"
	s="${s} --config-dir ${LE_CONFIG_DIR}"
	s="${s} --work-dir ${LE_WORK_DIR}"
	s="${s} --logs-dir ${LE_LOGS_DIR}"
	s="${s} --email ${LE_EMAIL}"
	s="${s} --webroot"

	ifs="$IFS"
	IFS=","

	for domain in $LE_DOMAINS; do
		s="${s} --webroot-path ${LE_WEBROOT_DIR}/${domain}"
		s="${s} --domain ${domain}"
	done

	IFS="$ifs"

	echo "$s"
}

reown() {
	archive_dir="$LE_CONFIG_DIR/archive"
	live_dir="$LE_CONFIG_DIR/live"
	renewal_dir="$LE_CONFIG_DIR/renewal"

	ifs="$IFS"
	IFS=","

	for domain in $LE_DOMAINS; do
		for dir in "$archive_dir" "$live_dir" "$renewal_dir"; do
			dir="$dir/$domain"
			if [ ! -d "$dir" ]; then
				continue
			fi

			file="$dir/chain"
			if ls "$file"* 1> /dev/null 2>&1; then
				chgrp nginx "$file"*
				chmod 644 "$file"*
			fi

			file="$dir/fullchain"
			if ls "$file"* 1> /dev/null 2>&1; then
				chgrp nginx "$file"*
				chmod 644 "$file"*
			fi

			file="$dir/privkey"
			if ls "$file"* 1> /dev/null 2>&1; then
				chgrp nginx "$file"*
				chmod 640 "$file"*
			fi
		done
	done

	IFS="$ifs"
}

schedule() {
	log "Scheduling a job to renew the certificate"

	entry_file=$(realpath "$0")
	log_file="$(dirname "$(realpath "$0")")/le.log"
	job="$LE_CRON \"$entry_file\" job >> \"$log_file\" 2>&1"

	table=$(crontab -l 2> /dev/null)
	if echo "$table" | grep -F "$job" > /dev/null 2>&1; then
		log "The job to renew the certificate is already scheduled"
		return
	fi

	(echo "$table"; echo "$job") | crontab -
	log "The job to renew the certificate has been scheduled"
}

job() {
	log "Running the job to renew the certificate"
	status=0
	rid=$(uuid)

	ping start "$rid"
	_=$(renew) || status=$?
	ping $status "$rid"

	log "The job to renew the certificate has been completed with the status '$status'"
	return $status
}

ping() {
	wget --output-document - --timeout 10 --tries 5 "$HC_URL$1?rid=$2"
}

uuid() {
	cat /proc/sys/kernel/random/uuid
}

log() {
	printf "%b" "[$(date +'%Y-%m-%d %H:%M:%S')] $1\n"
}

main "$@"
