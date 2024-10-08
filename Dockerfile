FROM alpine:3.20.3
COPY ae.sh /usr/local/bin/ae
RUN \
# Install dependencies
	apk add --no-cache --update docker openssl && \
	wget --no-verbose --output-document=/usr/local/bin/acme \
		https://raw.githubusercontent.com/acmesh-official/acme.sh/refs/tags/3.0.9/acme.sh && \
# Make scripts executable
	chmod +x /usr/local/bin/acme /usr/local/bin/ae
CMD ["tail", "-f", "/dev/null"]
