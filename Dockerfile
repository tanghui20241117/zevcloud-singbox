# ZevCloud Dockerfile build — VLESS + WebSocket (platform terminates TLS)
#
# ZevCloud docs (https://docs.zevcloud.net/guide/dockerfile):
#  - A Dockerfile in the service Root Directory is used as-is; Build Pack
#    becomes "Dockerfile"; the service Port is filled from EXPOSE.
#  - The app MUST bind to $PORT (injected by the platform) and listen on
#    0.0.0.0. EXPOSE, the runtime port and the service Port setting must
#    agree, or the service returns Bad Gateway.
#  - Build for linux/amd64. One container per service.
#  - Do NOT bake secrets into image layers: the live UUID should come
#    from the Variables tab at runtime (see entrypoint.sh + README.md).
#
# Free tier this targets: 512 MB RAM / 1 vCPU / 1 GB storage,
# build timeout 10 min, no sleep, unmetered bandwidth.

FROM alpine:3.21

# sing-box pinned to a known-good release (musl build = correct for Alpine).
# Do NOT use latest: a floating tag can change the binary under a rebuild.
ARG SING_BOX_VERSION=1.14.4
RUN apk add --no-cache ca-certificates jq \
 && wget -qO /tmp/sing-box.tar.gz \
      "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-amd64-musl.tar.gz" \
 && mkdir -p /tmp/sb \
 && tar -xzf /tmp/sing-box.tar.gz -C /tmp/sb \
 && mv "$(find /tmp/sb -name sing-box -type f | head -n 1)" /usr/local/bin/sing-box \
 && chmod +x /usr/local/bin/sing-box \
 && rm -rf /tmp/sing-box.tar.gz /tmp/sb \
 && sing-box version

COPY config.json /etc/sing-box/config.json
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default port. The platform injects $PORT at runtime and entrypoint.sh
# rewrites listen_port to it; 8080 is only the fallback when $PORT is unset.
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
