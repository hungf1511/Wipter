#!/bin/bash
set -euo pipefail

# Generate sing-box config only if proxy details are provided
if [ -n "${PROXY_HOST:-}" ] && [ -n "${PROXY_PORT:-}" ]; then
  echo "Proxy details found. Generating sing-box config..."
  AUTH_BLOCK=""
  if [ -n "${PROXY_USER:-}" ]; then
    AUTH_BLOCK=$(printf ',\n      "username": "%s",\n      "password": "%s"' "$PROXY_USER" "${PROXY_PASS:-}")
  fi

  cat > /app/sing-box.json <<EOF
{
  "log": {"level": "info"},
  "dns": {"servers": [{"address": "8.8.8.8", "detour": "direct"}]},
  "inbounds": [{
    "type": "tun",
    "tag": "tun-in",
    "interface_name": "tun0",
    "inet4_address": "198.18.0.1/15",
    "auto_route": false,
    "strict_route": false,
    "stack": "system"
  }],
  "outbounds": [
    {
      "type": "${PROXY_TYPE:-socks}",
      "tag": "proxy-out",
      "server": "${PROXY_HOST}",
      "server_port": ${PROXY_PORT}${AUTH_BLOCK}
    },
    {"type": "direct", "tag": "direct"}
  ],
  "route": {"rules": [
    {"protocol": "dns", "outbound": "direct"},
    {"inbound": ["tun-in"], "outbound": "proxy-out"}
  ]}
}
EOF
else
  echo "No proxy details provided. Skipping sing-box setup."
fi

# Start supervisor to manage all processes
/usr/bin/supervisord -c /etc/supervisor/conf.d/wipter.conf &
SUPERVISOR_PID=$!

# If proxy is configured, set up routing
if [ -f /app/sing-box.json ]; then
    echo "Waiting for tun0 interface..."
    COUNT=0
    while ! ip addr show tun0 >/dev/null 2>&1; do
      sleep 1
      COUNT=$((COUNT + 1))
      if [ "$COUNT" -gt 20 ]; then
        echo "Error: tun0 did not appear after 20 seconds. sing-box may have failed."
        kill $SUPERVISOR_PID
        exit 1
      fi
    done
    echo "tun0 interface is up."

    # Manual routing configuration
    OLD_GATEWAY=$(ip route | grep default | awk '{print $3}')
    if [ -n "$OLD_GATEWAY" ]; then
      echo "Configuring routes to bypass TUN for proxy and DNS..."
      ip route add "$PROXY_HOST" via "$OLD_GATEWAY"
      ip route add 8.8.8.8 via "$OLD_GATEWAY"
    fi

    ip route del default || true
    ip route add default dev tun0

    echo "Network routing configured to use proxy."
fi

# Wait for supervisor to exit
wait $SUPERVISOR_PID
