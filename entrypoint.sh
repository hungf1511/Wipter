#!/bin/bash
set -euo pipefail

SUPERVISOR_PRIMARY_CONFIG="/etc/supervisor/supervisord.conf"
SUPERVISOR_FALLBACK_CONFIG="/etc/supervisor/conf.d/supervisord.conf"
SUPERVISOR_CONFIG="$SUPERVISOR_PRIMARY_CONFIG"
SUPERVISOR_SOCKET="/var/run/supervisor.sock"

if [ ! -f "$SUPERVISOR_CONFIG" ] && [ -f "$SUPERVISOR_FALLBACK_CONFIG" ]; then
  SUPERVISOR_CONFIG="$SUPERVISOR_FALLBACK_CONFIG"
fi

################################################################################
# SING-BOX PROXY SETUP (Based on proxy-sdk)
################################################################################

# Generate sing-box config only if proxy details are provided
if [ -n "${PROXY_HOST:-}" ] && [ -n "${PROXY_PORT:-}" ]; then
  echo "Proxy details found. Generating sing-box config..."
  AUTH_BLOCK=""
  if [ -n "${PROXY_USER:-}" ]; then
    AUTH_BLOCK=$(printf ',\n      "username": "%s",\n      "password": "%s"' "$PROXY_USER" "${PROXY_PASS:-}")
  fi

  cat > /app/sing-box.json <<EOF
{
  "log": {"level": "info", "timestamp": true},
  "dns": {
    "servers": [
      {
        "tag": "google-dns",
        "address": "8.8.8.8",
        "detour": "direct"
      }
    ]
  },
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
      "type": "${PROXY_TYPE:-http}",
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
  # If no proxy, just start supervisor and exit
  exec /usr/bin/supervisord -c "$SUPERVISOR_CONFIG"
fi

################################################################################
# START SUPERVISOR & CONFIGURE NETWORK
################################################################################

# Start supervisor in the background to manage all services
/usr/bin/supervisord -c "$SUPERVISOR_CONFIG" &
SUPERVISOR_PID=$!

wait_for_supervisor() {
  for i in $(seq 1 20); do
    if [ -S "$SUPERVISOR_SOCKET" ]; then
      if supervisorctl -c "$SUPERVISOR_CONFIG" status >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 1
  done
  echo "Supervisor did not become ready in time."
  supervisorctl -c "$SUPERVISOR_CONFIG" status || true
  exit 1
}

wait_for_supervisor

# Use supervisorctl to start sing-box once supervisor is ready
supervisorctl -c "$SUPERVISOR_CONFIG" start sing-box

echo "Waiting for tun0 interface..."
COUNT=0
while ! ip addr show tun0 >/dev/null 2>&1; do
  sleep 1
  COUNT=$((COUNT + 1))
  if [ "$COUNT" -gt 15 ]; then
    echo "tun0 did not appear after 15 seconds. sing-box may have failed."
    supervisorctl -c "$SUPERVISOR_CONFIG" status
    cat /var/log/supervisor/sing-box*.log || true
    exit 1
  fi
done
echo "tun0 interface is up."

# Configure routing based on proxy-sdk logic
OLD_GATEWAY=$(ip route | grep default | awk '{print $3}')
if [ -n "$OLD_GATEWAY" ]; then
  echo "Configuring route for proxy host $PROXY_HOST via $OLD_GATEWAY"
  ip route add "$PROXY_HOST" via "$OLD_GATEWAY"
  echo "Configuring route for DNS server 8.8.8.8 via $OLD_GATEWAY"
  ip route add 8.8.8.8 via "$OLD_GATEWAY" || true
fi

# Force delete the default route and add the new one
ip route del default || true
ip route add default dev tun0 metric 50

echo "Routing configured. Final routing table:"
ip route

echo "Entrypoint setup complete. Services are running."

# Wait for supervisor to exit
wait $SUPERVISOR_PID
