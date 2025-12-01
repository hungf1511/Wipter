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

# Enable job control
set -m

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

echo "Starting Wipter....."
cd /root/wipter/
/root/wipter/wipter-app &

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

# Bring wipter-app to foreground (keep container running)
fg %/root/wipter/wipter-app

