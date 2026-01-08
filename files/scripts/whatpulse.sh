#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

ln -s /usr/lib64/libpcap.so /usr/lib/libpcap.so.0.8

log "Install whatpulse service."

# Create a temporary directory
TEMP_DIR=$(mktemp -d)

# Fetch the latest RPM URL
LATEST_URL=$(curl -s https://api.github.com/repos/whatpulse/linux-external-pcap-service/releases/latest | grep "browser_download_url" | grep "rpm" | cut -d '"' -f 4)

log "Downloading from: $LATEST_URL"

# Download the RPM to the temporary directory
curl -L -o "$TEMP_DIR/whatpulse-pcap-service.rpm" "$LATEST_URL"

# Install the RPM
dnf install "$TEMP_DIR/whatpulse-pcap-service.rpm"

# Clean up the temporary directory
rm -rf "$TEMP_DIR"

log "Installation complete."
