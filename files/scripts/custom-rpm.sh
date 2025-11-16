#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

log "Install Custom RPM file - Whatpulse Pcap Service"

curl -s https://api.github.com/repos/whatpulse/linux-external-pcap-service/releases/latest | jq -r '.assets[] | select(.name | endswith(".x86_64.rpm")) | .browser_download_url' | xargs curl -L -O
sudo rpm -i whatpulse-pcap-service-*.x86_64.rpm
