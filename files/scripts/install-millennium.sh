#!/usr/bin/env bash
set ${SET_X:+-x} -eou pipefail
trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG
log() {
    echo "=== $* ==="
}

RELEASE_TAG=$(curl -s "https://api.github.com/repos/SteamClientHomebrew/Millennium/releases/latest" | jq -r '.tag_name')
DOWNLOAD_URL="https://github.com/SteamClientHomebrew/Millennium/releases/download/${RELEASE_TAG}/millennium-${RELEASE_TAG}-linux-x86_64.tar.gz"

TEMP_DIR=$(mktemp -d)

curl -sSL "$DOWNLOAD_URL" -o "$TEMP_DIR/millennium.tar.gz"

tar -xzf "$TEMP_DIR/millennium.tar.gz" -C "$TEMP_DIR"

cp -rP "$TEMP_DIR/usr/"* /usr/

mkdir -p /usr/share/millennium-opt
cp -rP "$TEMP_DIR/opt/"* /usr/share/millennium-opt/

# extracts the exact python directory name safely using a bash glob
for dir in /usr/share/millennium-opt/python-i686*; do
    PYTHON_DIR=$(basename "$dir")
    break
done

# fixes execution permissions for the embedded python runtime
chmod +x "/usr/share/millennium-opt/${PYTHON_DIR}/bin/"*

# generates tmpfiles.d config to dynamically map opt into var/opt on boot
echo "C /var/opt/${PYTHON_DIR} - - - - /usr/share/millennium-opt/${PYTHON_DIR}" > /usr/lib/tmpfiles.d/millennium.conf

rm -rf "$TEMP_DIR"