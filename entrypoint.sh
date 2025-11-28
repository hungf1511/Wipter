#!/bin/bash
set -euo pipefail

REQUIRED_VARS=("PROXY_TYPE" "PROXY_HOST" "PROXY_PORT")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "Error: $var environment variable is required."
    exit 1
  fi
done

PROXY_TYPE_NORMALIZED=$(echo "${PROXY_TYPE}" | tr '[:upper:]' '[:lower:]')
case "$PROXY_TYPE_NORMALIZED" in
  http|https)
    PROXY_TYPE_VALUE="http"
    ;;
  socks|socks5)
    PROXY_TYPE_VALUE="socks"
    ;;
  *)
    echo "Error: Unsupported PROXY_TYPE '${PROXY_TYPE}'. Use http/https or socks/socks5."
    exit 1
    ;;
esac

AUTH_BLOCK=""
if [ -n "${PROXY_USER:-}" ]; then
  AUTH_BLOCK=$(printf ',\n      "username": "%s",\n      "password": "%s"' "$PROXY_USER" "${PROXY_PASS:-}")
fi

cat > /app/sing-box.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google-dns",
        "address": "8.8.8.8",
        "detour": "direct"
      }
    ]
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "inet4_address": "198.18.0.1/15",
      "auto_route": false,
      "strict_route": false,
      "stack": "system"
    }
  ],
  "outbounds": [
    {
      "type": "${PROXY_TYPE_VALUE}",
      "tag": "proxy-out",
      "server": "${PROXY_HOST}",
      "server_port": ${PROXY_PORT}${AUTH_BLOCK}
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "direct"
      },
      {
        "inbound": [
          "tun-in"
        ],
        "outbound": "proxy-out"
      }
    ]
  }
}
EOF

echo "sing-box configuration generated."

/usr/bin/supervisord -c /etc/supervisor/conf.d/wipter.conf &
SUPERVISOR_PID=$!

echo "Waiting for tun0 interface..."
COUNT=0
while ! ip addr show tun0 >/dev/null 2>&1; do
  sleep 1
  COUNT=$((COUNT + 1))
  if [ "$COUNT" -gt 20 ]; then
    echo "tun0 did not appear after 20 seconds. sing-box may have failed."
    kill "$SUPERVISOR_PID" >/dev/null 2>&1 || true
    wait "$SUPERVISOR_PID"
    exit 1
  fi
done
echo "tun0 interface is up."

ORIGINAL_GATEWAY=$(ip route show default | awk 'NR==1 {print $3}')
if [ -n "$ORIGINAL_GATEWAY" ]; then
  echo "Original default gateway: $ORIGINAL_GATEWAY"
  ip route add "$PROXY_HOST" via "$ORIGINAL_GATEWAY" >/dev/null 2>&1 || true
  ip route add 8.8.8.8 via "$ORIGINAL_GATEWAY" >/dev/null 2>&1 || true
else
  echo "Warning: Unable to detect original default gateway."
fi

sleep 1

for i in $(seq 1 5); do
  if ip route del default >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

ip route add default dev tun0 metric 50

echo "Routing configured. Current routes:"
ip route

wait "$SUPERVISOR_PID"






