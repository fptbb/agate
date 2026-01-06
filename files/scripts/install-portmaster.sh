#!/bin/sh

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

log "Installing Portmaster"

# ===================================
# STEP 1: Install Portmaster
# (install all necessary files)
# ===================================

# Create directory for binaries
mkdir -p /usr/lib/portmaster
cd /usr/lib/portmaster

# Download Portmaster UpdateManager utility
echo "[+] Downloading Portmaster UpdateManager..."
wget https://updates.safing.io/latest/linux_amd64/updatemgr/updatemgr
chmod a+x updatemgr

# Download latest binaries
echo "[+] Downloading Portmaster binaries..."
./updatemgr download https://updates.safing.io/stable.v3.json "/usr/lib/portmaster"
chmod a+x /usr/lib/portmaster/portmaster        # Ensure binary is executable
chmod a+x /usr/lib/portmaster/portmaster-core   # Ensure binary is executable

# Download latest data files
echo "[+] Downloading Portmaster data files..."
mkdir -p /var/lib/portmaster/intel
./updatemgr download https://updates.safing.io/intel.v3.json "/var/lib/portmaster/intel"

# (Optional)
# If the SELinux module is enabled, set correct SELinux context for the Portmaster core binary.
# This ensures the binary can be executed properly under SELinux policies, avoiding permission issues.
if command -v semanage >/dev/null 2>&1; then
    echo "[ ] Fixing SELinux permissions"
    semanage fcontext -a -t bin_t -s system_u $(realpath /usr/lib)'/portmaster/portmaster-core' || :
    restorecon -R /usr/lib/portmaster/portmaster-core 2>/dev/null >&2 || :
fi

# Clean up
rm -f /usr/lib/portmaster/updatemgr

# Done
echo "[i] At this point, Portmaster is installed."
echo "    You can start manually running the Portmaster daemon with:"
echo "        sudo /usr/lib/portmaster/portmaster-core --log-stdout"
echo "    To start User Interface, run:"
echo "        /usr/lib/portmaster/portmaster"

# ===================================
# STEP 2: Register Portmaster service
# (for systemd-based systems)
# ===================================

echo "[+] Registering Portmaster service"
cat <<EOF > /usr/lib/systemd/system/portmaster.service
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

systemctl daemon-reload
systemctl enable portmaster

# ===================================
# STEP 3: Register Portmaster UI
# (for desktop environments)
# ===================================

# Install Portmaster UI start script
echo "[+] Installing Portmaster UI start script"

cat <<EOF > /usr/lib/portmaster/portmaster-ui-start.sh
#!/bin/sh
WEBKIT_DISABLE_COMPOSITING_MODE=1 /usr/lib/portmaster/portmaster "$@"
EOF

chmod a+x /usr/lib/portmaster/portmaster-ui-start.sh
ln -sf /usr/lib/portmaster/portmaster-ui-start.sh /usr/bin/portmaster

# Register Portmaster UI in the system
echo "[+] Registering Portmaster UI .desktop file"

cat <<EOF > /usr/share/applications/portmaster.desktop
[Desktop Entry]
Name=Portmaster
GenericName=Application Firewall
Exec=/usr/bin/portmaster --with-prompts --with-notifications
Icon=portmaster
StartupWMClass=portmaster
Terminal=false
Type=Application
Categories=System
EOF

# Register Portmaster UI to automatically start on login
echo "[+] Registering Portmaster UI to start on login"

mkdir -p /etc/xdg/autostart

cat <<EOF > /etc/xdg/autostart/portmaster-autostart.desktop
[Desktop Entry]
Name=Portmaster
GenericName=Application Firewall Notifier
Exec=/usr/bin/portmaster --with-prompts --with-notifications --background
Icon=portmaster
Terminal=false
Type=Application
Categories=System
NoDisplay=true
EOF

# Register Portmaster icon
echo "[+] Registering Portmaster icon"
sudo wget https://raw.githubusercontent.com/safing/portmaster-packaging/master/linux/portmaster_logo.png -O /usr/share/pixmaps/portmaster.png

# ===================================
# Final notes
# ===================================

echo
cat <<'EOF'
[✓] Portmaster installation complete.

    NOTE:
    The Portmaster User Interface requires the following runtime libraries for tray integration and embedded web content:
      - AppIndicator (Ayatana / libappindicator) — system tray / indicator support
      - WebKitGTK 4.1 (libwebkit2gtk-4.1) — embedded web rendering
    Package names vary by distribution — use your distribution’s package manager or search tool to find the exact package names:
      - Debian / Ubuntu / openSUSE: `libayatana-appindicator3-1`, `libwebkit2gtk-4.1-0`
      - Fedora / RHEL: `libayatana-appindicator-gtk3`, `webkit2gtk4.1`
    If the UI fails to launch, verify the dependencies above are installed.
    You can run the UI from a terminal to view error output and diagnostics: `/usr/lib/portmaster/portmaster`
EOF
