#!/bin/sh

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

log "Installing ProtonVPN"

# adds the official protonvpn repository
cat <<EOF > /etc/yum.repos.d/protonvpn-stable.repo
[protonvpn-fedora-stable]
name=ProtonVPN Fedora Stable repository
baseurl=https://repo.protonvpn.com/fedora-\$releasever-stable/
enabled=1
type=rpm
repo_gpgcheck=1
gpgcheck=1
gpgkey=https://repo.protonvpn.com/fedora-\$releasever-stable/public_key.asc
EOF

# imports the gpg key to allow local validation
rpm --import https://repo.protonvpn.com/fedora-41-stable/public_key.asc

# installs the packages while blocking the failing post-transaction systemd hooks
dnf install -y --setopt=tsflags=noscripts proton-vpn-cli

log "ProtonVPN installation complete."