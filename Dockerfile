FROM alpine:latest

ARG NOVNC_VERSION="1.4.0" 
ARG OPENWRT_VERSION="23.05.2"
ARG VERSION_ARG "0.1"

RUN apk add --no-cache \
        bash \
        tini \
        wget \
        qemu-system-aarch64 \
        qemu-hw-usb-host \
        qemu-hw-usb-redirect \
        nginx \
        netcat-openbsd \
        python3 \
        py3-pip \
        py3-virtualenv \
    && mkdir -p /usr/share/novnc \
    && wget https://github.com/novnc/noVNC/archive/refs/tags/v${NOVNC_VERSION}.tar.gz -O /tmp/novnc.tar.gz -q \
    && tar -xf /tmp/novnc.tar.gz -C /tmp/ \
    && cd /tmp/noVNC-${NOVNC_VERSION}\
    && mv app core vendor package.json *.html /usr/share/novnc \
    && wget https://github.com/bugy/script-server/releases/download/1.18.0/script-server.zip \
    && unzip -o script-server.zip -d /usr/share/script-server \
    && python3 -m venv /var/lib/script-server-env \
    && source /var/lib/script-server-env/bin/activate \
    && pip install -r /usr/share/script-server/requirements.txt \
    && sed -i 's/^worker_processes.*/worker_processes 1;/' /etc/nginx/nginx.conf

# Get OpenWrt images
RUN mkdir /var/vm \ 
    && if [ "$OPENWRT_VERSION" = "master" ] ; then \
        wget "https://downloads.openwrt.org/snapshots/targets/armsr/armv8/openwrt-armsr-armv8-generic-ext4-rootfs.img.gz" \
        -O /var/vm/rootfs-${OPENWRT_VERSION}.img.gz \
        && wget "https://downloads.openwrt.org/snapshots/targets/armsr/armv8/openwrt-armsr-armv8-generic-kernel.bin" \
        -O /var/vm/kernel.bin ;\
    else \
        wget "https://archive.openwrt.org/releases/${OPENWRT_VERSION}/targets/armsr/armv8/openwrt-${OPENWRT_VERSION}-armsr-armv8-generic-ext4-rootfs.img.gz" \
        -O /var/vm/rootfs-${OPENWRT_VERSION}.img.gz \
        && wget "https://archive.openwrt.org/releases/${OPENWRT_VERSION}/targets/armsr/armv8/openwrt-${OPENWRT_VERSION}-armsr-armv8-generic-kernel.bin" \
        -O /var/vm/kernel.bin ;\
    fi
ENV OPENWRT_VERSION=${OPENWRT_VERSION}

COPY ./src /run/
COPY ./web /var/www/
COPY ./openwrt_additional /var/vm/openwrt_additional
COPY ./script-server /var/script-server

RUN chmod +x /run/*.sh

VOLUME /storage
EXPOSE 8006
EXPOSE 8000
EXPOSE 8022

RUN echo "$VERSION_ARG" > /run/version

ENTRYPOINT ["/sbin/tini", "-s", "/run/entry.sh"]
