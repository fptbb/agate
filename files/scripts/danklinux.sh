#!/usr/bin/env bash
set -ouex pipefail

echo "Configuring DankLinux (DMS) for Niri Wayland Session..."

# links the user services to start when niri starts
mkdir -p /usr/lib/systemd/user/niri.service.wants
ln -sf /usr/lib/systemd/user/dms.service /usr/lib/systemd/user/niri.service.wants/dms.service
ln -sf /usr/lib/systemd/user/dsearch.service /usr/lib/systemd/user/niri.service.wants/dsearch.service

# generates minimal portal configuration
mkdir -p /usr/share/xdg-desktop-portal
cat << 'EOF' > /usr/share/xdg-desktop-portal/niri-portals.conf
[preferred]
# handles all standard interfaces like openuri, secret, and filechooser implicitly
default=kde;gtk;

org.freedesktop.impl.portal.ScreenCast=wlr;
org.freedesktop.impl.portal.Screenshot=wlr;
org.freedesktop.impl.portal.RemoteDesktop=wlr;
EOF

echo "Portal configuration updated successfully."

# creates a wrapper script to safely inject environment variables before niri starts
cat << 'EOF' > /usr/bin/start-niri-agate
#!/usr/bin/env bash

export XDG_CURRENT_DESKTOP=niri
export KDE_SESSION_VERSION=6
export QT_QPA_PLATFORMTHEME=qt6ct
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

dbus-update-activation-environment --systemd XDG_CURRENT_DESKTOP KDE_SESSION_VERSION QT_QPA_PLATFORMTHEME QT_WAYLAND_DISABLE_WINDOWDECORATION

# consumes the pam socket created by sddm to unlock kdewallet automatically
/usr/libexec/pam_kwallet_init &

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