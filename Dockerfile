# builder container
FROM quay.io/centos/centos:stream9 as build

# Install set of dependencies to support building Xen Orchestra
RUN dnf update -y && \
    dnf install -y epel-release epel-next-release dnf-plugins-core && \
    dnf config-manager -y --set-enabled crb && \
    dnf -y groupinstall "Development Tools" && \
    dnf -y module enable nodejs:20 && \
    dnf install -y python3 libpng-devel ca-certificates git fuse yarnpkg

# Fetch Xen-Orchestra sources from git stable branch
RUN git clone -b master https://github.com/vatesfr/xen-orchestra /etc/xen-orchestra

# Run build tasks against sources
# Docker buildx QEMU arm64 emulation is slow, so we set timeout for yarn
RUN cd /etc/xen-orchestra && \
    yarn config set network-timeout 200000 && \
    yarn && \
    yarn build

# Install plugins
RUN find /etc/xen-orchestra/packages/ -maxdepth 1 -mindepth 1 -not -name "xo-server" -not -name "xo-web" -not -name "xo-server-cloud" -not -name "xo-server-test" -not -name "xo-server-test-plugin" -exec ln -s {} /etc/xen-orchestra/packages/xo-server/node_modules \;

# Runner container
FROM quay.io/centos/centos:stream9

MAINTAINER Bill Schouten <bschouten@ctlinux.com>

# Install set of dependencies for running Xen Orchestra
RUN dnf install -y dnf-plugins-core epel-release epel-next-release && \
    dnf copr enable -y areiter/fedora-epel-extra && \
    dnf update -y && \
    dnf install -y valkey-compat-redis libvhdi python3 python3-jinja2 lvm2 nfs-utils cifs-utils ca-certificates monit procps-ng ntfs-3g fuse-libs

RUN dnf module reset nodejs && \
    dnf module enable -y nodejs:18 && \
    dnf module install -y nodejs:18/common

# Install forever for starting/stopping Xen-Orchestra
RUN npm install forever -g

# Copy built xen orchestra from builder
COPY --from=build /etc/xen-orchestra /etc/xen-orchestra

# Logging
RUN ln -sf /proc/1/fd/1 /var/log/valkey/valkey.log && \
    ln -sf /proc/1/fd/1 /var/log/xo-server.log && \
    ln -sf /proc/1/fd/1 /var/log/monit.log

# Healthcheck
ADD healthcheck.sh /healthcheck.sh
RUN chmod +x /healthcheck.sh


HEALTHCHECK --start-period=1m --interval=30s --timeout=5s --retries=2 CMD /healthcheck.sh

# Copy xo-server configuration template
ADD conf/xo-server.toml.j2 /xo-server.toml.j2

# Copy monit configuration
ADD conf/monit-services /etc/monit.d/services

RUN echo "include /etc/monit.d/*" > /etc/monitrc

# Copy startup script
ADD run.sh /run.sh
RUN chmod +x /run.sh

WORKDIR /etc/xen-orchestra/packages/xo-server

EXPOSE 80

CMD ["/run.sh"]
