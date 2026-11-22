#!/bin/sh
# ZevCloud entrypoint for the fleet sing-box node.
#
# Jobs at container start (before sing-box launches):
#  1. Bind to the platform-injected $PORT (ZevCloud sets PORT on every
#     service; the docs require reading it, never hard-coding a port).
#     Falls back to 8080 (the EXPOSE value) when $PORT is unset.
#  2. Optional runtime UUID override: if VLESS_UUID is set in the
#     service's Variables tab, it replaces the UUID baked into
#     config.json. Use this to keep the live credential out of the
#     image layer (ZevCloud docs: don't bake secrets into images).
#  3. Optional runtime domain override: if VLESS_DOMAIN is set in the
#     Variables tab, it replaces the WebSocket Host header in
#     config.json. Set it to the service's real *.zevcloud.app domain.
#  4. Validate the final config with `sing-box check`, then exec sing-box.
set -eu

CONFIG="/etc/sing-box/config.json"

PORT="${PORT:-8080}"
case "$PORT" in
  ''|*[!0-9]*)
    echo "entrypoint: invalid PORT value: '$PORT'" >&2
    exit 1
    ;;
esac

# 1) listen port := $PORT
jq --argjson port "$PORT" \
  '.inbounds[0].listen_port = $port' \
  "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"

# 2) UUID override (optional, recommended for production use)
if [ -n "${VLESS_UUID:-}" ]; then
  jq --arg uuid "$VLESS_UUID" \
    '.inbounds[0].users[0].uuid = $uuid' \
    "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  echo "entrypoint: UUID taken from VLESS_UUID env var"
fi

# 3) WS Host header override (optional, needed when the service domain
#    differs from the one baked into config.json at render time)
if [ -n "${VLESS_DOMAIN:-}" ]; then
  jq --arg host "$VLESS_DOMAIN" \
    '.inbounds[0].transport.headers.Host = $host' \
    "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  echo "entrypoint: WS Host header set to $VLESS_DOMAIN"
fi

sing-box check -c "$CONFIG"
exec sing-box run -c "$CONFIG"
