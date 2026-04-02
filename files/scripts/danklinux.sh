#!/usr/bin/env bash
set -ouex pipefail

echo "Configuring DankLinux (DMS) for Niri Wayland Session..."

# links the user services to start when niri starts
mkdir -p /usr/lib/systemd/user/niri.service.wants
ln -sf /usr/lib/systemd/user/dms.service /usr/lib/systemd/user/niri.service.wants/dms.service
ln -sf /usr/lib/systemd/user/dsearch.service /usr/lib/systemd/user/niri.service.wants/dsearch.service

ln -sf /usr/lib/systemd/user/plasma-kwallet-pam.service /usr/lib/systemd/user/niri.service.wants/plasma-kwallet-pam.service

# uses gnome keyring
# ln -sf /usr/lib/systemd/user/gnome-keyring-daemon.service /usr/lib/systemd/user/niri.service.wants/gnome-keyring-daemon.service
# ln -sf /usr/lib/systemd/user/gnome-keyring-daemon.socket /usr/lib/systemd/user/niri.service.wants/gnome-keyring-daemon.socket

PORTAL_CONF="/usr/share/xdg-desktop-portal/niri-portals.conf"

if [ ! -f "$PORTAL_CONF" ]; then
    echo "Configuration file not found at $PORTAL_CONF"
    exit 1
fi

sed -i 's/^default=.*/default=kde;gtk;wlr/' "$PORTAL_CONF"
sed -i 's/^org.freedesktop.impl.portal.Access=.*/org.freedesktop.impl.portal.Access=kde;gtk;/' "$PORTAL_CONF"
sed -i 's/^org.freedesktop.impl.portal.Notification=.*/org.freedesktop.impl.portal.Notification=kde;gtk;/' "$PORTAL_CONF"
sed -i 's/^org.freedesktop.impl.portal.Secret=.*/org.freedesktop.impl.portal.Secret=kde;/' "$PORTAL_CONF"

echo "Portal configuration updated successfully."

NIRI_DESKTOP="/usr/share/wayland-sessions/niri.desktop"

# intercepts niri launch directly within the session file to inject variables before services start
if [ -f "$NIRI_DESKTOP" ]; then
    sed -i 's|^Exec=.*|Exec=sh -c "export XDG_CURRENT_DESKTOP=niri QT_QPA_PLATFORMTHEME=qt6ct QT_WAYLAND_DISABLE_WINDOWDECORATION=1; dbus-update-activation-environment --systemd XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME QT_WAYLAND_DISABLE_WINDOWDECORATION; exec niri-session"|' "$NIRI_DESKTOP"
    echo "Niri desktop file updated successfully."
else
    echo "Niri desktop file not found at $NIRI_DESKTOP"
fi

echo "NIRI CONFIG DONE"