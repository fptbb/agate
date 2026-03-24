#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

# log "Updating AppImage Updater..."
# Use alternative url with jsdelivr to avoid github rate limits
# curl -sL https://cdn.jsdelivr.net/gh/fptbb/fp-appimage-updater@latest/install.sh | bash -s -- --system --no-systemd
# log "AppImage Updater updated successfully."

# appends a new path before the closing bracket of the existing array
sed -i 's|^\(paths = \[.*\)\]|\1, "/etc/ublue-os/fp-topgrade.toml"]|' /usr/share/ublue-os/topgrade.toml

cat <<EOF > /etc/ublue-os/fp-topgrade.toml
[commands]
"AppImage Updater" = "fp-appimage-updater update"
EOF