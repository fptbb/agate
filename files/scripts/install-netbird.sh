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
sudo dnf config-manager addrepo --from-repofile=/etc/yum.repos.d/netbird.repo

# installs the packages while blocking the failing post-transaction systemd hooks
dnf install -y --setopt=tsflags=noscripts netbird netbird-ui

log "Netbird installation complete."