#!/usr/bin/env bash
set ${SET_X:+-x} -eou pipefail
trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG
log() {
    echo "=== $* ==="
}

URL="https://malachite.fpt.icu/images.json"
CONFIG="/usr/share/agate/malachite.json"

echo "Fetching Malachite image index..."

mkdir -p "$(dirname "$CONFIG")"
curl -fsSL "$URL" -o "$CONFIG"

IMAGES=$(jq -r '.images | keys[]' "$CONFIG")

echo "Generating Malachite Desktop Launchers..."

for NAME in $IMAGES; do
    PRETTY=$(jq -r --arg n "$NAME" '.images[$n].title' "$CONFIG")

    cat <<DESK > "/usr/share/applications/malachite-$NAME.desktop"
[Desktop Entry]
Name=Malachite $PRETTY
Comment=Enter the $PRETTY-based Malachite distrobox
Exec=distrobox enter $NAME
Icon=utilities-terminal
Type=Application
Categories=Development;System;TerminalEmulator;
Terminal=true
Actions=Update;Recreate;Setup;

[Desktop Action Update]
Name=Update Container
Exec=ujust malachite-update $NAME
Terminal=true

[Desktop Action Recreate]
Name=Recreate (Wipe State)
Exec=ujust malachite-recreate $NAME
Terminal=true

[Desktop Action Setup]
Name=Setup / Replace
Exec=ujust malachite-setup $NAME
Terminal=true
DESK
    echo "Generated malachite-$NAME.desktop"
done

echo "Configuring Malachite Persistence (tmpfiles)..."

# tmpfiles configuration
cat <<TMP > /usr/lib/tmpfiles.d/agate.conf
# Create persistent directory for Agate system data
# Type Path Mode User Group Age Argument
d /var/lib/agate 0777 root root - -
TMP

echo "Malachite setup complete."
