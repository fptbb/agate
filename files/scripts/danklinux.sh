#!/usr/bin/env bash
set -ouex pipefail

echo "Configuring DankLinux (DMS) for Niri Wayland Session..."

# Link the user services to start when niri starts
mkdir -p /usr/lib/systemd/user/niri.service.wants
ln -sf /usr/lib/systemd/user/dms.service /usr/lib/systemd/user/niri.service.wants/dms.service
ln -sf /usr/lib/systemd/user/dsearch.service /usr/lib/systemd/user/niri.service.wants/dsearch.service

ln -sf /usr/lib/systemd/user/plasma-kwallet-pam.service /usr/lib/systemd/user/niri.service.wants/plasma-kwallet-pam.service

# Use gnome keyring
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