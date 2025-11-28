FROM docker.io/ubuntu:22.04

ARG SING_BOX_VERSION=1.8.0
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

# Install essential packages, including D-Bus, X11, keytar dependencies, and networking tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget tini xdotool gpg openbox ca-certificates \
    python3-pip python3-venv git supervisor \
    dbus dbus-x11 gnome-keyring libsecret-1-0 libsecret-1-dev \
    nodejs npm build-essential dos2unix binutils \
    iproute2 iptables iputils-ping net-tools curl \
    libnspr4 libnss3 libxss1 libssl-dev libatk-bridge2.0-0 libgbm1 libasound2 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /tmp/.X11-unix /run/dbus /root/.local/share/keyrings /root/.cache /app /var/log/supervisor
RUN chmod 1777 /tmp/.X11-unix && chmod 755 /run/dbus

# Install TurboVNC
RUN wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey | gpg --dearmor > /etc/apt/trusted.gpg.d/TurboVNC.gpg && \
    wget -q -O /etc/apt/sources.list.d/turbovnc.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list && \
    apt-get update && apt-get install -y turbovnc && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install sing-box
RUN wget -q -O /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp && \
    mv "/tmp/sing-box-${SING_BOX_VERSION}-linux-${TARGETARCH}/sing-box" /usr/local/bin/sing-box && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/sing-box*

# Download and install Wipter
RUN mkdir -p /root/wipter && \
    wget -q -O /tmp/wipter.tar.gz "https://provider-assets.wipter.com/latest/linux/${TARGETARCH}/wipter-app-${TARGETARCH}.tar.gz" && \
    tar -xzf /tmp/wipter.tar.gz -C /root/wipter --strip-components=1 && \
    rm /tmp/wipter.tar.gz

# Copy scripts and configs
COPY start.sh /app/start.sh
COPY entrypoint.sh /app/entrypoint.sh
COPY supervisord.conf /etc/supervisor/conf.d/wipter.conf
RUN chmod +x /app/start.sh /app/entrypoint.sh

# Default environment variables
ENV PROXY_TYPE=""
ENV PROXY_HOST=""
ENV PROXY_PORT=""
ENV PROXY_USER=""
ENV PROXY_PASS=""
ENV WIPTER_EMAIL=""
ENV WIPTER_PASSWORD=""

WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
