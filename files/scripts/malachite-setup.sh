#!/usr/bin/env bash

set -euo pipefail

CONFIG="/usr/share/agate/malachite.json"

if [[ ! -f "$CONFIG" ]]; then
    echo "Error: Malachite config not found at $CONFIG"
    exit 1
fi

IMAGES=$(jq -c '.images[]' "$CONFIG")

echo "Generating Malachite Desktop Launchers..."

for img in $IMAGES; do
    NAME=$(echo "$img" | jq -r '.name')
    PRETTY=$(echo "$img" | jq -r '.pretty_name')
    
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
