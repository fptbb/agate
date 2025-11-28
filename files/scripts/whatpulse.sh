#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

ln -s /usr/lib64/libpcap.so /usr/lib/libpcap.so.0.8

# log "Build whatpulse service."

# git clone https://github.com/whatpulse/linux-external-pcap-service.git
# cd ./linux-external-pcap-service
# make
# install -m 755 ./whatpulse-pcap-service /usr/bin/whatpulse-pcap-service
# install -m 644 ./whatpulse-pcap-service.service /lib/systemd/system/whatpulse-pcap-service.service
