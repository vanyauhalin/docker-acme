#!/bin/sh

log() {
	printf "%b" "$(date +'%Y/%m/%d %H:%M:%S') $1\n"
}

log "hi"
info "hola"
