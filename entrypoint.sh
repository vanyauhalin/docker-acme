#!/bin/sh

set -ue

echo \
	"$HC_URL" \
	"$LE_CONFIG_DIR" \
	"$LE_CRON" \
	"$LE_DOMAINS" \
	"$LE_EMAIL" \
	"$LE_LOGS_DIR" \
	"$LE_WEBROOT_DIR" \
	"$LE_WORK_DIR" \
	> /dev/null

./le.sh options
./le.sh dirs
./le.sh self

(
	sleep 5
	./le.sh unself
	./le.sh job
	crond
) &

exec "$@"
