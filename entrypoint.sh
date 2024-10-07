#!/bin/sh

set -ue

echo \
	"$LE_HEALTHCHECKS_URL" \
	"$LE_CONFIG_DIR" \
	"$LE_CRON" \
	"$LE_DOMAINS" \
	"$LE_EMAIL" \
	"$LE_LOGS_DIR" \
	"$LE_WEBROOT_DIR" \
	"$LE_WORK_DIR" \
	> /dev/null

./le.sh dirs
./le.sh self

(
	sleep 5
	./le.sh unself
	./le.sh schedule
	crond
) &

exec "$@"
