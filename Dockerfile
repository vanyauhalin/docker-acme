ARG ACME_VERSION=3.0.9
FROM alpine:3.20.3
ARG ACME_VERSION
COPY ae.sh /usr/local/bin/ae
RUN \
# Install dependencies
	apk add --no-cache --update curl openssl && \
	curl --output /usr/local/bin/acme \
		"https://raw.githubusercontent.com/acmesh-official/acme.sh/refs/tags/$ACME_VERSION/acme.sh" && \
# Make scripts executable
	chmod +x /usr/local/bin/acme /usr/local/bin/ae
CMD ["tail", "-f", "/dev/null"]
