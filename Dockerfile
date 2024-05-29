FROM alpine:latest

ARG NOVNC_VERSION="1.4.0" 
ARG OPENWRT_VERSION="23.05.3"
ARG VERSION_ARG="0.1"

RUN mkdir -p /tmp/noVNC-${NOVNC_VERSION}
ADD https://github.com/novnc/noVNC/archive/refs/tags/v${NOVNC_VERSION}.tar.gz /tmp/novnc.tar.gz
ADD https://github.com/bugy/script-server/releases/download/1.18.0/script-server.zip /tmp/noVNC-${NOVNC_VERSION}/script-server.zip

RUN apk add --no-cache \
        supervisor \
        bash \
        wget \
        qemu-system-aarch64 \
        qemu-hw-usb-host \
        qemu-hw-usb-redirect \
        nginx \
        netcat-openbsd \
        python3 \
        py3-pip \
        py3-virtualenv \
        uuidgen \
        caddy \
    && mkdir -p /usr/share/novnc \
    && tar -xf /tmp/novnc.tar.gz -C /tmp/ \
    && cd /tmp/noVNC-${NOVNC_VERSION}\
    && mv app core vendor package.json *.html /usr/share/novnc \
    && unzip -o script-server.zip -d /usr/share/script-server \
    && python3 -m venv /var/lib/script-server-env \
    && source /var/lib/script-server-env/bin/activate \
    && pip install -r /usr/share/script-server/requirements.txt \
    && sed -i 's/^worker_processes.*/worker_processes 1;daemon off;/' /etc/nginx/nginx.conf
    
# Get OpenWrt images
RUN mkdir /var/vm \ 
    mkdir /var/vm/packages \
    && if [ "$OPENWRT_VERSION" = "master" ] ; then \
        wget "https://downloads.openwrt.org/snapshots/targets/armsr/armv8/openwrt-armsr-armv8-generic-ext4-rootfs.img.gz" \
        -O /var/vm/rootfs-${OPENWRT_VERSION}.img.gz \
        && wget "https://downloads.openwrt.org/snapshots/targets/armsr/armv8/openwrt-armsr-armv8-generic-kernel.bin" \
        -O /var/vm/kernel.bin \
        && wget "https://downloads.openwrt.org/snapshots/targets/armsr/armv8/openwrt-armsr-armv8-rootfs.tar.gz" \
        -O /tmp/rootfs-${OPENWRT_VERSION}.tar.gz ; \
    else \
        wget "https://archive.openwrt.org/releases/${OPENWRT_VERSION}/targets/armsr/armv8/openwrt-${OPENWRT_VERSION}-armsr-armv8-generic-ext4-rootfs.img.gz" \
        -O /var/vm/rootfs-${OPENWRT_VERSION}.img.gz \
        && wget "https://archive.openwrt.org/releases/${OPENWRT_VERSION}/targets/armsr/armv8/openwrt-${OPENWRT_VERSION}-armsr-armv8-generic-kernel.bin" \
        -O /var/vm/kernel.bin \ 
        && wget "https://archive.openwrt.org/releases/${OPENWRT_VERSION}/targets/armsr/armv8/openwrt-${OPENWRT_VERSION}-armsr-armv8-rootfs.tar.gz" \ 
        -O /tmp/rootfs-${OPENWRT_VERSION}.tar.gz ; \
    fi \
    \
    # Use OpenWrt rootfs to download additional IPKs and put them into the Docker image
    && mkdir /tmp/openwrt-rootfs \
    && tar -xzf /tmp/rootfs-${OPENWRT_VERSION}.tar.gz -C /tmp/openwrt-rootfs \
    && cp /etc/resolv.conf /tmp/openwrt-rootfs/etc/resolv.conf \
    && chroot /tmp/openwrt-rootfs mkdir -p /var/lock \
    && chroot /tmp/openwrt-rootfs opkg update \
    # Download Luci and qemu guest agent \
    && chroot /tmp/openwrt-rootfs opkg install qemu-ga luci usbutils --download-only \
    # Download Wi-Fi access point support and Wi-Fi USB devices support \
    && chroot /tmp/openwrt-rootfs opkg install hostapd wpa-supplicant kmod-mt7921u --download-only \
    # Download celluar network support \
    && chroot /tmp/openwrt-rootfs opkg install modemmanager kmod-usb-net-qmi-wwan luci-proto-modemmanager qmi-utils --download-only \
    # Copy downloaded IPKs into the Docker image \
    && cp /tmp/openwrt-rootfs/*.ipk /var/vm/packages \
    && rm -rf /tmp/openwrt-rootfs \
    && rm /tmp/rootfs-${OPENWRT_VERSION}.tar.gz \
    && echo "OPENWRT_VERSION=\"${OPENWRT_VERSION}\"" > /var/vm/openwrt_metadata.conf \
    && echo "OPENWRT_IMAGE_CREATE_DATETIME=\"`date`\"" >> /var/vm/openwrt_metadata.conf \
    && echo "OPENWRT_IMAGE_ID=\"`uuidgen`\"" >> /var/vm/openwrt_metadata.conf

COPY supervisord.conf /etc/supervisord.conf
COPY ./src /run/
COPY ./web /var/www/
COPY ./openwrt_additional /var/vm/openwrt_additional
COPY ./script-server /var/script-server

RUN chmod +x /run/*.sh

VOLUME /storage
EXPOSE 8006
EXPOSE 8000
EXPOSE 8022

RUN echo "$VERSION_ARG" > /run/version \
    && echo "CONTAINER_CREATE_DATETIME=\"`date`\"" >> /var/vm/openwrt_metadata.conf

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
