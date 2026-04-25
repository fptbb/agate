#!/usr/bin/env bash
set -ouex pipefail

# Keep the x86_64 virtualization stack without dragging the full multi-arch
# emulation set back in. common-debloat.yml removes the extra qemu targets.
dnf5 --setopt=install_weak_deps=False install -y \
    edk2-ovmf

# Keep the DX carry-over focused on dev and desktop tooling that still applies
# now that the image no longer inherits from the deck/gamemode branch.
if [[ -f /usr/share/applications/input-remapper-gtk.desktop ]]; then
    sed -i 's@^NoDisplay=true@NoDisplay=false@' /usr/share/applications/input-remapper-gtk.desktop
fi

mkdir -p /etc/modules-load.d
cat <<'EOF' > /etc/modules-load.d/ip_tables.conf
iptable_nat
EOF
