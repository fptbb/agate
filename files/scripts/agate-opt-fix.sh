#!/usr/bin/env bash
set -euo pipefail

# Match the bazzite-dx /opt relocation for packages that still write into
# /var/opt during build, while staying harmless when there is nothing to move.
mkdir -p /usr/lib/opt

for dir in /var/opt/*/; do
    [[ -d "$dir" ]] || continue
    name=$(basename "$dir")
    mv "$dir" "/usr/lib/opt/$name"
    echo "L+ /var/opt/$name - - - - /usr/lib/opt/$name" >> /usr/lib/tmpfiles.d/opt-fix.conf
done
