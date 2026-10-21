#!/usr/bin/env bash
set ${SET_X:+-x} -eou pipefail
trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG
log() {
    echo "=== $* ==="
}

# OVMF firmware for the qemu/libvirt stack installed by this recipe.
dnf5 --setopt=install_weak_deps=False install -y \
    edk2-ovmf

# input-remapper ships hidden; unhide it so it is usable from the launcher.
if [[ -f /usr/share/applications/input-remapper-gtk.desktop ]]; then
    sed -i 's@^NoDisplay=true@NoDisplay=false@' /usr/share/applications/input-remapper-gtk.desktop
fi

mkdir -p /etc/modules-load.d
cat <<'EOF' > /etc/modules-load.d/ip_tables.conf
iptable_nat
EOF
