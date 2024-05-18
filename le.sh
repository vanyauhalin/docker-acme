#!/bin/sh

set -ue

main() {
	cmd=${1-""}
	if [ "$cmd" = "" ];        then help;    return 1; fi
	if [ "$cmd" = "help" ];    then help;    return;   fi
	log "Executing the '$cmd' command"
	if [ "$cmd" = "options" ]; then options; return;   fi
	# shellcheck disable=SC3044
	if [ "$cmd" = "dirs" ];    then dirs;    return;   fi
	if [ "$cmd" = "self" ];    then self;    return;   fi
	if [ "$cmd" = "unself" ];  then unself;  return;   fi
	if [ "$cmd" = "test" ];    then test;    return;   fi
	if [ "$cmd" = "prod" ];    then prod;    return;   fi
	if [ "$cmd" = "job" ];     then job;     return;   fi
	if [ "$cmd" = "renew" ];   then renew;   return;   fi
	log "Unknown the command '$cmd'"
	return 1
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
	file=$(realpath "$0")
	dir=$(dirname "$file")
	sh="#!/bin/sh\n"
	sh="$sh\"$file\" options >> \"$dir/le.log\" 2>&1\n"
	sh="$sh\"$file\" renew >> \"$dir/le.log\" 2>&1\n"
	file=/etc/periodic/weekly/le
	printf "%b" "$sh" > "$file"
	chmod +x "$file"
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
}

log() {
	printf "%b" "[$(date +'%Y-%m-%d %H:%M:%S')] $1\n"
}

main "$@"
