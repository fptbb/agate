#!/usr/bin/env bash
set -ouex pipefail

echo "Configuring DankLinux (DMS) for Niri Wayland Session..."

# links the user services to start when niri starts
mkdir -p /usr/lib/systemd/user/niri.service.wants
ln -sf /usr/lib/systemd/user/dms.service /usr/lib/systemd/user/niri.service.wants/dms.service
ln -sf /usr/lib/systemd/user/dsearch.service /usr/lib/systemd/user/niri.service.wants/dsearch.service

ln -sf /usr/lib/systemd/user/plasma-kwallet-pam.service /usr/lib/systemd/user/niri.service.wants/plasma-kwallet-pam.service

# generates portal configuration prioritizing kde
mkdir -p /usr/share/xdg-desktop-portal
cat << 'EOF' > /usr/share/xdg-desktop-portal/niri-portals.conf
[preferred]
default=kde;gtk;wlr
org.freedesktop.impl.portal.Access=kde;gtk;
org.freedesktop.impl.portal.Notification=kde;gtk;
org.freedesktop.impl.portal.Secret=kde;
EOF

echo "Portal configuration updated successfully."

# creates a wrapper script to safely inject environment variables before niri starts
cat << 'EOF' > /usr/bin/start-niri-agate
#!/usr/bin/env bash

export XDG_CURRENT_DESKTOP=niri
export QT_QPA_PLATFORMTHEME=qt6ct
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

dbus-update-activation-environment --systemd XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME QT_WAYLAND_DISABLE_WINDOWDECORATION

exec niri-session
EOF

# ensures the wrapper is executable
chmod +x /usr/bin/start-niri-agate

NIRI_DESKTOP="/usr/share/wayland-sessions/niri.desktop"

# updates the desktop entry to use the new wrapper script
if [ -f "$NIRI_DESKTOP" ]; then
    sed -i 's|^Exec=.*|Exec=/usr/bin/start-niri-agate|' "$NIRI_DESKTOP"
    echo "Niri desktop file updated successfully."
else
    echo "Niri desktop file not found at $NIRI_DESKTOP"
fi

echo "NIRI CONFIG DONE"