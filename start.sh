#!/bin/bash

# Check if WIPTER_EMAIL and WIPTER_PASSWORD are set
if [ -z "$WIPTER_EMAIL" ]; then
    echo "Error: WIPTER_EMAIL environment variable is not set."
    exit 1
fi

if [ -z "$WIPTER_PASSWORD" ]; then
    echo "Error: WIPTER_PASSWORD environment variable is not set."
    exit 1
fi

# Start a D-Bus session
eval "$(dbus-launch --sh-syntax)"

# Unlock the GNOME Keyring daemon (non-interactively)
echo 'mypassword' | gnome-keyring-daemon --unlock --replace

# Clean up lock files
rm -f /tmp/.X1-lock
rm -rf /tmp/.X11-unix

# Set up the VNC password
if [ -z "$VNC_PASSWORD" ]; then
    echo "VNC_PASSWORD environment variable is not set. Using a random password."
    VNC_PASSWORD="$(tr -dc '[:alpha:]' < /dev/urandom | fold -w "${1:-8}" | head -n1)"
fi
mkdir -p ~/.vnc
echo -n "$VNC_PASSWORD" | /opt/TurboVNC/bin/vncpasswd -f > ~/.vnc/passwd
chmod 400 ~/.vnc/passwd
unset VNC_PASSWORD

# Set VNC port from environment variable or default to 5900
VNC_PORT=${VNC_PORT:-5900}

# Set Websockify port from environment variable or default to 6080
WEBSOCKIFY_PORT=${WEBSOCKIFY_PORT:-6080}

# Start TurboVNC server and websockify
if [ "$WEB_ACCESS_ENABLED" == "true" ]; then
    /opt/TurboVNC/bin/vncserver -rfbauth ~/.vnc/passwd -geometry 1200x800 -rfbport "${VNC_PORT}" -wm openbox :1 || {
        echo "Error: Failed to start TurboVNC server on port ${VNC_PORT}"
        exit 1
    }
    /opt/venv/bin/websockify --web=/noVNC "${WEBSOCKIFY_PORT}" localhost:"${VNC_PORT}" &
else
    /opt/TurboVNC/bin/vncserver -rfbauth ~/.vnc/passwd -geometry 1200x800 -rfbport "${VNC_PORT}" -wm openbox :1 || {
        echo "Error: Failed to start TurboVNC server on port ${VNC_PORT}"
        exit 1
    }
fi

export DISPLAY=:1

start_wipter_app() {
    echo "Starting Wipter....."
    cd /root/wipter/
    /root/wipter/wipter-app &
    WIPTER_PID=$!
    export WIPTER_PID
    echo "Wipter started with PID ${WIPTER_PID}"
}

start_wipter_app

if ! [ -f ~/.wipter-configured ]; then
    # Wait for the wipter window to be available
    while [[ "$(xdotool search --name Wipter| wc -l)" -lt 3 ]]; do
        sleep 10
    done

    # Handle wipter login
    xdotool search --name Wipter | tail -n1 | xargs xdotool windowfocus
    sleep 5
    xdotool key Tab
    sleep 3
    xdotool key Tab
    sleep 3
    xdotool key Tab
    sleep 3
    xdotool type "$WIPTER_EMAIL"
    sleep 3
    xdotool key Tab
    sleep 3
    xdotool type "$WIPTER_PASSWORD"
    sleep 3
    xdotool key Return
    sleep 5
    xdotool search --name Wipter | tail -n1 | xargs xdotool windowclose

    touch ~/.wipter-configured
fi

################################################################################
# AUTO-RESTART WIPTER MỖI 24H - VERSION FIXED (ĐÓNG GUI CŨ)
################################################################################

restart_wipter() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Restarting Wipter to clear memory..."
    
    # BƯỚC 1: Kill process wipter-app
    echo "Killing wipter-app process..."
    pkill -f "wipter-app"
    
    sleep 5
    
    # BƯỚC 2: Start wipter-app lại (GUI tự động mở, session tự động load)
    echo "Starting wipter-app..."
    start_wipter_app
    
    # BƯỚC 3: Đợi GUI mở xong
    echo "Waiting for GUI to open..."
    sleep 10
    
    # BƯỚC 4: Đóng GUI đi (như lúc auto-login, để không lag)
    echo "Closing GUI..."
    xdotool search --name Wipter | tail -n1 | xargs xdotool windowclose
    
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Wipter restarted successfully (process running, GUI closed, RAM cleared)"
}

# Run auto-restart every 24 hours in background
(
    while true; do
        sleep 86400  # 24 hours
        restart_wipter
    done
) &

RESTART_PID=$!
echo "✅ Auto-restart monitor started (PID: $RESTART_PID, interval: 24h)"

monitor_wipter() {
    while true; do
        CURRENT_PID="$WIPTER_PID"
        if [ -z "$CURRENT_PID" ]; then
            echo "No Wipter PID found, exiting."
            exit 1
        fi

        wait "$CURRENT_PID"
        EXIT_CODE=$?

        if [ "$CURRENT_PID" = "$WIPTER_PID" ]; then
            echo "Wipter process ${CURRENT_PID} exited with code ${EXIT_CODE}"
            exit "$EXIT_CODE"
        fi
        # If PID changed (e.g., due to scheduled restart), loop to wait on the new one
    done
}

monitor_wipter

