# Usage Reporter image for GCP Marketplace billing
# Contains: mc (MinIO client), curl, jq
FROM alpine:3.19

RUN apk add --no-cache \
    curl \
    jq \
    ca-certificates \
    && wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc

ENTRYPOINT ["/bin/sh"]
