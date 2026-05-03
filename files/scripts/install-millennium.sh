#!/usr/bin/env bash
set -ouex pipefail

RELEASE_TAG=$(curl -s "https://api.github.com/repos/SteamClientHomebrew/Millennium/releases/latest" | jq -r '.tag_name')
DOWNLOAD_URL="https://github.com/SteamClientHomebrew/Millennium/releases/download/${RELEASE_TAG}/millennium-${RELEASE_TAG}-linux-x86_64.tar.gz"

mkdir -p /tmp/millennium
curl -sSL "$DOWNLOAD_URL" -o /tmp/millennium/millennium.tar.gz

tar -xzf /tmp/millennium/millennium.tar.gz -C /tmp/millennium

cp -rP /tmp/millennium/usr/* /usr/

mkdir -p /usr/share/millennium-opt
cp -rP /tmp/millennium/opt/* /usr/share/millennium-opt/

# extracts the exact python directory name safely using a bash glob
for dir in /usr/share/millennium-opt/python-i686*; do
    PYTHON_DIR=$(basename "$dir")
    break
done

# fixes execution permissions for the embedded python runtime
chmod +x "/usr/share/millennium-opt/${PYTHON_DIR}/bin/"*

# generates tmpfiles.d config to dynamically map opt into var/opt on boot
echo "C /var/opt/${PYTHON_DIR} - - - - /usr/share/millennium-opt/${PYTHON_DIR}" > /usr/lib/tmpfiles.d/millennium.conf

rm -rf /tmp/millennium