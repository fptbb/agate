#!/usr/bin/env bash
set ${SET_X:+-x} -eou pipefail
trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG
log() { echo "=== $* ==="; }

log "Installing Nix packages"
dnf install -y nix nix-daemon nix-legacy

log "Writing default nix.conf"
cat > /etc/nix/nix.conf <<'EOF'
trusted-users = root @wheel
sandbox = true
extra-experimental-features = nix-command flakes
EOF

log "Writing tmpfiles rule to recreate /var/nix on boot"
mkdir -p /usr/lib/tmpfiles.d
cat > /usr/lib/tmpfiles.d/nix.conf <<'EOF'
d /var/nix 0755 root root -
EOF

log "Writing nix.mount unit"
cat > /usr/lib/systemd/system/nix.mount <<'EOF'
[Unit]
Description=Mount /nix
DefaultDependencies=no
RequiresMountsFor=/var
Before=local-fs.target nix-store-init.service nix-daemon.service

[Mount]
What=/var/nix
Where=/nix
Type=none
Options=bind

[Install]
WantedBy=local-fs.target
EOF

log "Writing nix-store-init unit"
cat > /usr/lib/systemd/system/nix-store-init.service <<'EOF'
[Unit]
Description=Initialize Nix store
After=nix.mount
Requires=nix.mount
Before=nix-daemon.service
ConditionPathExists=!/nix/store

[Service]
Type=oneshot
ExecStart=/usr/bin/nix-store --init
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

log "Overriding nix-daemon.service to wait on our store-init unit"
mkdir -p /usr/lib/systemd/system/nix-daemon.service.d
cat > /usr/lib/systemd/system/nix-daemon.service.d/10-wait-for-store-init.conf <<'EOF'
[Unit]
After=nix-store-init.service
Requires=nix-store-init.service
EOF

log "Enabling nix.mount"
systemctl enable nix.mount

log "Enabling nix-store-init.service"
systemctl enable nix-store-init.service

log "Enabling nix-daemon.service"
systemctl enable nix-daemon.service

## Old installation method (commented out) for reference
# mkdir -p /nix && \
# 	curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix -o /nix/determinate-nix-installer.sh && \
# 	chmod a+rx /nix/determinate-nix-installer.sh
