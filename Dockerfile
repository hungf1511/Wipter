FROM docker.io/ubuntu:latest

ARG SING_BOX_VERSION=1.8.0
ARG TARGETARCH

# Install essential packages, including full D-Bus, X11, keytar dependencies, supervisor, networking tools, and dos2unix
RUN apt-get -y update && apt-get -y --no-install-recommends --no-install-suggests install \
    wget tini xdotool gpg openbox ca-certificates \
    python3-pip python3-venv \
    git supervisor \
    # D-Bus, GNOME Keyring, and keytar dependencies
    dbus dbus-x11 gnome-keyring libsecret-1-0 libsecret-1-dev \
    # Node.js and build tools for keytar
    nodejs npm build-essential \
    # dos2unix for line ending conversion
    dos2unix \
    # Tools for wipter package download and networking
    binutils iproute2 iptables && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create /tmp/.X11-unix and /run/dbus directories
RUN mkdir -p /tmp/.X11-unix /run/dbus && \
    chmod 1777 /tmp/.X11-unix && \
    chmod 755 /run/dbus

# Create directories for keyring and cache
RUN mkdir -p /root/.local/share/keyrings /root/.cache

# Create a virtual environment and install Python dependencies
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir websockify keyring

# Update CA certificates
RUN update-ca-certificates

# Copy noVNC files
RUN git clone https://github.com/novnc/noVNC.git /noVNC && \
    ln -s /noVNC/vnc_lite.html /noVNC/index.html

# Install TurboVNC
RUN wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey | gpg --dearmor > /etc/apt/trusted.gpg.d/TurboVNC.gpg && \
    wget -q -O /etc/apt/sources.list.d/turbovnc.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list && \
    apt-get -y update && apt-get -y install turbovnc libwebkit2gtk-4.1-0 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Download the wipter package based on architecture
RUN case "${TARGETARCH}" in \
      amd64) wget -q -O /tmp/wipter-app.tar.gz https://provider-assets.wipter.com/latest/linux/x64/wipter-app-x64.tar.gz ;; \
      arm64) wget -q -O /tmp/wipter-app.tar.gz https://provider-assets.wipter.com/latest/linux/arm64/wipter-app-arm64.tar.gz ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    mkdir -p /root/wipter && \
    tar -xzf /tmp/wipter-app.tar.gz -C /root/wipter --strip-components=1 && \
    rm /tmp/wipter-app.tar.gz

# Install system dependencies for wipter and wipter.deb
RUN apt-get -y update && \
    apt-get -y install curl iputils-ping net-tools apt-transport-https libnspr4 libnss3 libxss1 libssl-dev && \
    apt-get -y --fix-broken --no-install-recommends --no-install-suggests install && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install sing-box
RUN wget -q -O /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp && \
    mv "/tmp/sing-box-${SING_BOX_VERSION}-linux-${TARGETARCH}/sing-box" /usr/local/bin/sing-box && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/sing-box*

# Copy the start script
COPY start.sh /root/

# Convert start.sh to Unix line endings and make it executable
RUN dos2unix /root/start.sh && \
    chmod +x /root/start.sh

# Expose the necessary ports
EXPOSE 5900 6080

# Copy sing-box supervisor/entrypoint assets
RUN mkdir -p /app
COPY entrypoint.sh /app/entrypoint.sh
COPY supervisord.conf /etc/supervisor/conf.d/wipter.conf
RUN chmod +x /app/entrypoint.sh

# Default environment variables for proxy configuration
ENV PROXY_TYPE="" \
    PROXY_HOST="" \
    PROXY_PORT="" \
    PROXY_USER="" \
    PROXY_PASS=""

ENTRYPOINT ["/app/entrypoint.sh"]
