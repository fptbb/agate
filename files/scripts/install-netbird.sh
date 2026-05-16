#!/bin/sh

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

log "Installing Netbird"

# adds the official netbird repository
cat <<EOF > /etc/yum.repos.d/netbird.repo
[netbird]
name=netbird
baseurl=https://pkgs.netbird.io/yum/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
repo_gpgcheck=1
EOF

# imports the gpg key to allow local validation
rpm --import https://pkgs.netbird.io/yum/repodata/repomd.xml.key

# installs the packages while blocking the failing post-transaction systemd hooks
dnf install -y --setopt=tsflags=noscripts netbird netbird-ui

log "Creating systemd service for Netbird"

# defines systemd unit since postinstall scripts were skipped by noscripts flag
cat <<EOF > /usr/lib/systemd/system/netbird.service
[Unit]
Description=NetBird Daemon
Documentation=https://netbird.io/docs
After=network-online.target syslog.target NetworkManager.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/netbird service run --config /etc/netbird/config.json --log-file /var/log/netbird/client.log
Restart=on-failure
RestartSec=5
TimeoutStopSec=10

# provisions transient /var directories at runtime to prevent boot crashes on atomic layouts
CacheDirectory=netbird
LogsDirectory=netbird
RuntimeDirectory=netbird
StateDirectory=netbird

[Install]
WantedBy=multi-user.target
EOF

log "Enabling Netbird service"

# enables service statically at build time since systemctl enable fails inside container builds
mkdir -p /usr/lib/systemd/system/multi-user.target.wants
ln -s ../netbird.service /usr/lib/systemd/system/multi-user.target.wants/netbird.service

log "Netbird installation complete."