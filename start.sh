#!/bin/bash
set -e

# Check for required environment variables
if [ -z "$WIPTER_EMAIL" ] || [ -z "$WIPTER_PASSWORD" ]; then
    echo "Error: WIPTER_EMAIL and WIPTER_PASSWORD environment variables must be set."
    exit 1
fi

# Start a D-Bus session required for GNOME Keyring
echo "Starting D-Bus session..."
eval "$(dbus-launch --sh-syntax)"

# Start and unlock the GNOME Keyring daemon
# The password here is arbitrary and used only to unlock the daemon non-interactively.
echo "Starting GNOME Keyring daemon..."
echo "dummy-password" | gnome-keyring-daemon --unlock --replace

# Clean up any stale VNC lock files
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Set up the VNC password (using a fixed password for simplicity)
mkdir -p /root/.vnc
echo "wipter" | /opt/TurboVNC/bin/vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd

# Start the TurboVNC server with Openbox window manager
# This creates a virtual display :1
/opt/TurboVNC/bin/vncserver :1 -geometry 1280x800 -rfbauth /root/.vnc/passwd -wm openbox

# Set the DISPLAY environment variable so GUI apps know where to open
export DISPLAY=:1

# Start the Wipter application in the background
echo "Starting Wipter application..."
/root/wipter/wipter-app &

# Automated login using xdotool
# This only runs if a marker file doesn't exist
if ! [ -f /root/.wipter-configured ]; then
    echo "Performing first-time login automation..."
    
    # Wait for the Wipter window to appear
    for i in {1..30}; do
        if xdotool search --name "Wipter" &>/dev/null; then
            echo "Wipter window found."
            break
        fi
        echo "Waiting for Wipter window... ($i/30)"
        sleep 2
    done

    WINDOW_ID=$(xdotool search --name "Wipter" | tail -1)
    if [ -n "$WINDOW_ID" ]; then
        xdotool windowfocus "$WINDOW_ID"
        sleep 3
        xdotool type "$WIPTER_EMAIL"
        sleep 3
        xdotool key Tab
        sleep 3
        xdotool type "$WIPTER_PASSWORD"
        sleep 3
        xdotool key Return
        echo "Login credentials submitted."
        
        # Create a marker file to prevent this from running again
        touch /root/.wipter-configured
    else
        echo "Warning: Could not find Wipter window to automate login."
    fi
fi

# Keep the script running to monitor the main process
echo "Wipter setup complete. VNC server is running on port 5901."
# Wait for any background process to exit, which keeps the script alive
wait -n
