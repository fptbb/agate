#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

log "Build whatpulse service."

git clone https://github.com/whatpulse/linux-external-pcap-service.git
cd ./linux-external-pcap-service
make
chmod +755 ./whatpulse-pcap-service
chmod +644 ./whatpulse-pcap-service-manual.service
cp ./whatpulse-pcap-service /usr/bin/whatpulse-pcap-service
cp ./whatpulse-pcap-service.service /lib/systemd/system/whatpulse-pcap-service.service
