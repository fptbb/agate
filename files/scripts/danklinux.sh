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

mkdir -p /etc/environment.d
echo 'QT_QPA_PLATFORMTHEME=qt6ct' > /etc/environment.d/99-qt_theme.conf