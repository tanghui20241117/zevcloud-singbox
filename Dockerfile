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
# Free tier this targets: 512 MB RAM / 1 vCPU / 1 GB storage,
# build timeout 10 min, no sleep, unmetered bandwidth.
#
# Build note (CVE-2026-33186): the prebuilt sing-box v1.14.4 release binary
# bundles google.golang.org/grpc v1.79.1, which carries CVE-2026-33186
# (CRITICAL, gRPC-Go authorization bypass). Komuta's security scan fails
# the build on any CRITICAL finding, and a downloaded binary cannot be
# patched. sing-box is therefore compiled here from the v1.14.4 source
# with grpc bumped to v1.79.3 (the fixed version). The sing-box version
# itself is unchanged and still pinned: do NOT use latest, a floating
# tag can change the binary under a rebuild.

# ---- build stage: compile sing-box v1.14.4 from source ----
FROM golang:1.25-alpine AS builder

ARG SING_BOX_VERSION=1.14.4

RUN set -eux; \
    apk add --no-cache ca-certificates git; \
    wget -qO /tmp/sing-box-src.tar.gz \
      "https://github.com/SagerNet/sing-box/archive/refs/tags/v${SING_BOX_VERSION}.tar.gz"; \
    mkdir -p /src; \
    tar -xzf /tmp/sing-box-src.tar.gz -C /src --strip-components=1; \
    rm -f /tmp/sing-box-src.tar.gz

WORKDIR /src

# Bump grpc to the CVE-fixed version, then build a static binary.
# Build tags match the upstream release build (full feature set).
# Note: with_ech and with_reality_server were removed in sing-box v1.14.4
# (ECH moved to stdlib; Reality Server merged into with_utls) — passing
# them makes the build fail, so they are intentionally left out.
RUN set -eux; \
    export CGO_ENABLED=0; \
    mkdir -p /out; \
    go mod edit -require=google.golang.org/grpc@v1.79.3; \
    go mod tidy; \
    go build -trimpath -ldflags "-s -w -buildid=" \
      -tags "with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_v2ray_api" \
      -o /out/sing-box ./cmd/sing-box; \
    /out/sing-box version

# ---- runtime stage: identical to the previous image ----
FROM alpine:3.21

COPY --from=builder /out/sing-box /usr/local/bin/sing-box

RUN apk add --no-cache ca-certificates jq \
 && chmod +x /usr/local/bin/sing-box \
 && sing-box version

COPY config.json /etc/sing-box/config.json
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default port. The platform injects $PORT at runtime and entrypoint.sh
# rewrites listen_port to it; 8080 is only the fallback when $PORT is unset.
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
