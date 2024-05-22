#!/bin/sh

main() {
	rid=$(cat /proc/sys/kernel/random/uuid)
	ping start "$rid"
	./le.sh options
	./le.sh renew
	ping $? "$rid"
}

ping() {
	wget --output-document - --timeout 10 --tries 5 "$HC_URL$1?rid=$2"
}

main "$@"
