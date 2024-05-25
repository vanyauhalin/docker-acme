#!/bin/sh

set -ue

help() {
	echo "Usage: le.sh <command>"
	echo
	echo "Subcommands:"
	echo "  help     Show this help message"
	echo "  options  Show the letsencrypt options"
	echo "  dirs     Create the letsencrypt directories"
	echo "  self     Generate a self-signed certificate"
	echo "  unself   Remove the self-signed certificate"
	echo "  test     Obtain a test certificate"
	echo "  prod     Obtain a production certificate"
	echo "  job      Schedule a job to renew the certificate"
	echo "  renew    Renew the certificate"
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
	"options")
		options
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
	"job")
		job
		;;
	"renew")
		renew
		;;
	*)
		log "Unknown the command '$1'"
		return 1
		;;
	esac
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

dirs() {
	mkdir -p \
		"$LE_CONFIG_DIR" \
		"$LE_LOGS_DIR" \
		"$LE_WEBROOT_DIR" \
		"$LE_WORK_DIR" \
		"$(live_dir)" \
		"$(self_dir)"
	ifs="$IFS"
	IFS=","
	for domain in $LE_DOMAINS; do
		dir="${LE_WEBROOT_DIR}/${domain}"
		mkdir -p "$dir"
	done
	IFS="$ifs"
}

self() {
	live_dir=$(live_dir)
	if [ ! -d "$live_dir" ]; then
		log "The '$live_dir' directory does not exist"
		return 1
	fi

	self_dir=$(self_dir)
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

		for name in "chain" "fullchain" "privkey"; do
			ln -s "$self/$name.pem" "$live/$name.pem"
			chmod 777 "$live/$name.pem"
		done
	done

	IFS="$ifs"
}

unself() {
	live_dir=$(live_dir)
	if [ ! -d "$live_dir" ]; then
		log "The '$live_dir' directory does not exist"
		return 1
	fi

	self_dir=$(self_dir)
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

		for name in "chain" "fullchain" "privkey"; do
			link="$live/$name.pem"
			traget=$(realpath "$link")
			rm "$link" "$traget"
		done

		rmdir "$live" "$self"
	done

	IFS="$ifs"
}

test() {
	# shellcheck disable=SC2046
	certbot certonly --staging $(options)
	reown
	nginx -s reload
}

prod() {
	# shellcheck disable=SC2046
	certbot certonly $(options)
	reown
	nginx -s reload
}

job() {
	job="$LE_CRON \"$(job_file)\" >> \"$(log_file)\" 2>&1"
	ls=$(crontab -l 2> /dev/null)
	if ! echo "$ls" | grep -F "$job" > /dev/null 2>&1; then
		(echo "$ls"; echo "$job") | crontab -
	fi
}

renew() {
	certbot renew --non-interactive
	reown
	nginx -s reload
}

reown() {
	archive_dir=$(archive_dir)
	live_dir=$(live_dir)
	renewal_dir=$(renewal_dir)

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

archive_dir() {
	echo "$LE_CONFIG_DIR/archive"
}

live_dir() {
	echo "$LE_CONFIG_DIR/live"
}

renewal_dir() {
	echo "$LE_CONFIG_DIR/renewal"
}

self_dir() {
	file=$(realpath "$0")
	dir=$(dirname "$file")
	echo "$dir/self"
}

job_file() {
	file=$(realpath "$0")
	dir=$(dirname "$file")
	echo "$dir/job.sh"
}

log_file() {
	file=$(realpath "$0")
	dir=$(dirname "$file")
	echo "$dir/le.log"
}

log() {
	printf "%b" "[$(date +'%Y-%m-%d %H:%M:%S')] $1\n"
}

main "$@"
