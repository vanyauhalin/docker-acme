FROM alpine:3.20.3
COPY ae.sh /usr/local/bin/ae
RUN \
# Install dependencies
# acme.sh has an incompatibility with the BusyBox wget implementation
# https://github.com/acmesh-official/acme.sh/issues/5319/
	apk add --no-cache --update docker openssl wget && \
	wget --no-verbose --output-document=/usr/local/bin/acme \
		https://raw.githubusercontent.com/acmesh-official/acme.sh/refs/tags/3.0.9/acme.sh && \
# Make scripts executable
	chmod +x /usr/local/bin/acme /usr/local/bin/ae
CMD ["tail", "-f", "/dev/null"]
