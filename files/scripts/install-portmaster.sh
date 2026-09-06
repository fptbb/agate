#!/usr/bin/env bash
set -euo pipefail

# ===================================
# Install Portmaster on BlueBuild / Bazzite (Fedora Atomic)
# Adapted from https://wiki.safing.io/en/Portmaster/Install/Linux
# ===================================

echo "[+] Installing Portmaster runtime dependencies..."
# UI dependencies mentioned in the official notes
dnf5 -y install \
    webkit2gtk4.1 \
    libayatana-appindicator-gtk3 \
    || dnf -y install \
    webkit2gtk4.1 \
    libayatana-appindicator-gtk3

# ===================================
# STEP 1: Install Portmaster binaries & data
# ===================================

echo "[+] Creating directories..."
mkdir -p /usr/lib/portmaster
mkdir -p /var/lib/portmaster/intel
mkdir -p /var/lib/portmaster/log

cd /usr/lib/portmaster

# Download Portmaster UpdateManager utility
echo "[+] Downloading Portmaster UpdateManager..."
curl -fL --retry 5 -o updatemgr \
    https://updates.safing.io/latest/linux_amd64/updatemgr/updatemgr
chmod a+x updatemgr

# Download latest binaries
echo "[+] Downloading Portmaster binaries..."
./updatemgr download https://updates.safing.io/stable.v3.json "/usr/lib/portmaster"
chmod a+x /usr/lib/portmaster/portmaster
chmod a+x /usr/lib/portmaster/portmaster-core

# Download latest data files (intel)
echo "[+] Downloading Portmaster data files..."
./updatemgr download https://updates.safing.io/intel.v3.json "/var/lib/portmaster/intel"

# SELinux context (safe to run even if not needed)
if command -v semanage >/dev/null 2>&1; then
    echo "[+] Fixing SELinux permissions for portmaster-core..."
    semanage fcontext -a -t bin_t -s system_u "$(realpath /usr/lib)/portmaster/portmaster-core" || true
    restorecon -R /usr/lib/portmaster/portmaster-core 2>/dev/null || true
fi

# Clean up temporary tool
rm -f /usr/lib/portmaster/updatemgr

echo "[i] Portmaster binaries and data installed."

# ===================================
# STEP 2: Register Portmaster systemd service
# ===================================

echo "[+] Installing portmaster.service..."
cat > /usr/lib/systemd/system/portmaster.service << 'EOF'
[Unit]
Description=Portmaster by Safing
Documentation=https://safing.io
Documentation=https://docs.safing.io
Before=nss-lookup.target network.target shutdown.target
After=systemd-networkd.service
Conflicts=shutdown.target
Conflicts=firewalld.service
Wants=nss-lookup.target

[Service]
Type=simple
Restart=on-failure
RestartSec=10
RestartPreventExitStatus=24
LockPersonality=yes
MemoryDenyWriteExecute=yes
MemoryLow=2G
NoNewPrivileges=yes
PrivateTmp=yes
PIDFile=/var/lib/portmaster/core-lock.pid
Environment=LOGLEVEL=info
Environment=PORTMASTER_ARGS=
EnvironmentFile=-/etc/default/portmaster
ProtectSystem=true
ReadWritePaths=/usr/lib/portmaster
RestrictAddressFamilies=AF_UNIX AF_NETLINK AF_INET AF_INET6
RestrictNamespaces=yes
ProtectHome=read-only
ProtectKernelTunables=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
PrivateDevices=yes
AmbientCapabilities=cap_chown cap_kill cap_net_admin cap_net_bind_service cap_net_broadcast cap_net_raw cap_sys_module cap_sys_ptrace cap_dac_override cap_fowner cap_fsetid cap_sys_resource cap_bpf cap_perfmon
CapabilityBoundingSet=cap_chown cap_kill cap_net_admin cap_net_bind_service cap_net_broadcast cap_net_raw cap_sys_module cap_sys_ptrace cap_dac_override cap_fowner cap_fsetid cap_sys_resource cap_bpf cap_perfmon
StateDirectory=portmaster
WorkingDirectory=/var/lib/portmaster
ExecStart=/usr/lib/portmaster/portmaster-core --log-dir=/var/lib/portmaster/log -- $PORTMASTER_ARGS
ExecStopPost=-/usr/lib/portmaster/portmaster-core -recover-iptables

[Install]
WantedBy=multi-user.target
EOF

# Enable the service so it starts on boot after the image is deployed
systemctl enable portmaster.service

# ===================================
# STEP 3: Register Portmaster UI
# ===================================

echo "[+] Installing Portmaster UI start script..."
cat > /usr/lib/portmaster/portmaster-ui-start.sh << 'EOF'
#!/bin/sh
WEBKIT_DISABLE_COMPOSITING_MODE=1 /usr/lib/portmaster/portmaster "$@"
EOF
chmod a+x /usr/lib/portmaster/portmaster-ui-start.sh
ln -sf /usr/lib/portmaster/portmaster-ui-start.sh /usr/bin/portmaster

echo "[+] Installing .desktop files..."
cat > /usr/share/applications/portmaster.desktop << 'EOF'
[Desktop Entry]
Name=Portmaster
GenericName=Application Firewall
Exec=/usr/bin/portmaster --with-prompts --with-notifications
Icon=portmaster
StartupWMClass=portmaster
Terminal=false
Type=Application
Categories=System;
EOF

mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/portmaster-autostart.desktop << 'EOF'
[Desktop Entry]
Name=Portmaster
GenericName=Application Firewall Notifier
Exec=/usr/bin/portmaster --with-prompts --with-notifications --background
Icon=portmaster
Terminal=false
Type=Application
Categories=System;
NoDisplay=true
EOF

echo "[+] Installing Portmaster icon..."
mkdir -p /usr/share/pixmaps
curl -fL --retry 5 -o /usr/share/pixmaps/portmaster.png \
    https://raw.githubusercontent.com/safing/portmaster-packaging/master/linux/portmaster_logo.png

# ===================================
# Done
# ===================================

echo
echo "[✓] Portmaster installation complete."
echo "    Service enabled: portmaster.service"
echo "    UI launcher:     portmaster  (or from the application menu)"
echo "    Autostart:       enabled via /etc/xdg/autostart"