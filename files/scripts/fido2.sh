#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

# Your code goes here.
log 'forces fido2 module into initramfs'

# The fido2 module is needed for u2f support in browsers and other applications. This script adds the fido2 module to the dracut configuration so that it will be included in the initramfs.
mkdir -p /usr/lib/dracut.conf.d/
echo 'add_dracutmodules+=" fido2 "' > /usr/lib/dracut.conf.d/10-fido2.conf