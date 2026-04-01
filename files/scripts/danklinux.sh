#!/usr/bin/env bash
set -ouex pipefail

echo "Configuring DankLinux (DMS) for Niri Wayland Session..."

# Link the user services to start when niri starts
mkdir -p /usr/lib/systemd/user/niri.service.wants
ln -sf /usr/lib/systemd/user/dms.service /usr/lib/systemd/user/niri.service.wants/dms.service
ln -sf /usr/lib/systemd/user/dsearch.service /usr/lib/systemd/user/niri.service.wants/dsearch.service

ln -sf /usr/lib/systemd/user/gnome-keyring-daemon.service /usr/lib/systemd/user/niri.service.wants/gnome-keyring-daemon.service
ln -sf /usr/lib/systemd/user/gnome-keyring-daemon.socket /usr/lib/systemd/user/niri.service.wants/gnome-keyring-daemon.socket