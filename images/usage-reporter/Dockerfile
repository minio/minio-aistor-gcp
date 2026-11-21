# Usage Reporter image for GCP Marketplace billing
# Contains: mc (MinIO client), curl, jq
FROM alpine:3.19

RUN apk add --no-cache \
    curl \
    jq \
    ca-certificates \
    && MC_URL=https://dl.min.io/aistor/mc/release/linux-amd64/mc \
    && curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 \
         --speed-limit 10240 --speed-time 60 -o /usr/local/bin/mc "$MC_URL" \
    && echo "$(curl -fsSL --retry 5 "$MC_URL.sha256sum" | cut -d' ' -f1)  /usr/local/bin/mc" | sha256sum -c - \
    && chmod +x /usr/local/bin/mc

ENTRYPOINT ["/bin/sh"]
