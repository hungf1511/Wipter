FROM docker.io/ubuntu:latest

ARG SING_BOX_VERSION=1.8.0
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

# Install essential packages, including supervisor and sing-box dependencies
RUN apt-get -y update && apt-get -y --no-install-recommends --no-install-suggests install \
    wget tini xdotool gpg openbox ca-certificates supervisor scrot \
    python3-pip python3-venv git \
    dbus dbus-x11 gnome-keyring libsecret-1-0 libsecret-1-dev \
    nodejs npm build-essential dos2unix binutils \
    iproute2 iptables iputils-ping net-tools curl apt-transport-https \
    libnspr4 libnss3 libxss1 libssl-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /tmp/.X11-unix /run/dbus /root/.local/share/keyrings /root/.cache /app /var/log/supervisor && \
    chmod 1777 /tmp/.X11-unix && \
    chmod 755 /run/dbus

# Create a virtual environment and install Python dependencies
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir websockify keyring

# Update CA certificates and install noVNC
RUN update-ca-certificates && \
    git clone https://github.com/novnc/noVNC.git /noVNC && \
    ln -s /noVNC/vnc_lite.html /noVNC/index.html

# Install TurboVNC
RUN wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey | gpg --dearmor > /etc/apt/trusted.gpg.d/TurboVNC.gpg && \
    wget -q -O /etc/apt/sources.list.d/turbovnc.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list && \
    apt-get -y update && apt-get -y install turbovnc libwebkit2gtk-4.1-0 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install sing-box
RUN wget -q -O /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp && \
    mv "/tmp/sing-box-${SING_BOX_VERSION}-linux-${TARGETARCH}/sing-box" /usr/local/bin/sing-box && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/sing-box*

# Download the wipter package based on architecture
RUN case "${TARGETARCH}" in \
      amd64) wget -q -O /tmp/wipter-app.tar.gz https://provider-assets.wipter.com/latest/linux/x64/wipter-app-x64.tar.gz ;; \
      arm64) wget -q -O /tmp/wipter-app.tar.gz https://provider-assets.wipter.com/latest/linux/arm64/wipter-app-arm64.tar.gz ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    mkdir -p /root/wipter && \
    tar -xzf /tmp/wipter-app.tar.gz -C /root/wipter --strip-components=1 && \
    rm /tmp/wipter-app.tar.gz

# Copy scripts and configs
COPY entrypoint.sh /app/entrypoint.sh
COPY start.sh /app/start.sh
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN dos2unix /app/start.sh /app/entrypoint.sh && chmod +x /app/start.sh /app/entrypoint.sh

# Default environment variables
ENV PROXY_TYPE="http"
ENV PROXY_HOST=""
ENV PROXY_PORT=""
ENV PROXY_USER=""
ENV PROXY_PASS=""
ENV WIPTER_EMAIL=""
ENV WIPTER_PASSWORD=""
ENV VNC_PASSWORD=""

# Expose the necessary ports
EXPOSE 5900 6080

WORKDIR /app
ENTRYPOINT ["tini", "--", "/app/entrypoint.sh"]
