#!/usr/bin/env bash
set -ouex pipefail

echo "Configuring DankLinux (DMS) for Niri Wayland Session..."

# links user services to start on niri launch
mkdir -p /usr/lib/systemd/user/niri.service.wants
ln -sf /usr/lib/systemd/user/dms.service /usr/lib/systemd/user/niri.service.wants/dms.service
ln -sf /usr/lib/systemd/user/dsearch.service /usr/lib/systemd/user/niri.service.wants/dsearch.service

ln -sf /usr/lib/systemd/user/plasma-kwallet-pam.service /usr/lib/systemd/user/niri.service.wants/plasma-kwallet-pam.service

# generates portal configuration prioritizing kde
mkdir -p /usr/share/xdg-desktop-portal
cat << 'EOF' > /usr/share/xdg-desktop-portal/niri-portals.conf
[preferred]
default=kde;gtk;
org.freedesktop.impl.portal.ScreenCast=gnome;
org.freedesktop.impl.portal.Screenshot=gnome;
org.freedesktop.impl.portal.Access=kde;gtk;
org.freedesktop.impl.portal.Notification=kde;gtk;
org.freedesktop.impl.portal.Secret=kde;
EOF

echo "Portal configuration updated successfully."

# creates wrapper script to inject environment variables before niri starts
cat << 'EOF' > /usr/bin/start-niri-agate
#!/usr/bin/env bash

export XDG_CURRENT_DESKTOP=niri
export QT_QPA_PLATFORMTHEME=qt6ct
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# imports pam socket environments to systemd before niri triggers kwallet pam service
systemctl --user import-environment PAM_KWALLET_LOGIN PAM_KWALLET5_LOGIN
dbus-update-activation-environment --systemd XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME QT_WAYLAND_DISABLE_WINDOWDECORATION PAM_KWALLET_LOGIN PAM_KWALLET5_LOGIN

niri-session

# cleans up dbus activation environment to guarantee zero interference with plasma
systemctl --user unset-environment XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME QT_WAYLAND_DISABLE_WINDOWDECORATION PAM_KWALLET_LOGIN PAM_KWALLET5_LOGIN
dbus-update-activation-environment --systemd XDG_CURRENT_DESKTOP=KDE QT_QPA_PLATFORMTHEME=kde QT_WAYLAND_DISABLE_WINDOWDECORATION=
EOF

# ensures wrapper is executable
chmod +x /usr/bin/start-niri-agate

NIRI_DESKTOP="/usr/share/wayland-sessions/niri.desktop"

# updates desktop entry to use the new wrapper script
if [ -f "$NIRI_DESKTOP" ]; then
    sed -i 's|^Exec=.*|Exec=/usr/bin/start-niri-agate|' "$NIRI_DESKTOP"
    echo "Niri desktop file updated successfully."
else
    echo "Niri desktop file not found at $NIRI_DESKTOP"
fi

echo "NIRI CONFIG DONE"