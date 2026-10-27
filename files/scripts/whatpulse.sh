#!/usr/bin/env bash
# Installs WhatPulse External PCap Service into the immutable /usr tree.
set -euo pipefail

if (( EUID != 0 )); then
  echo 'ERROR: This script must run as root during the BlueBuild image build.' >&2
  exit 1
fi

# Follow GitHub's latest non-prerelease release on every image build.
# This is a floating version, not a reproducible version pin.
RELEASE_API='https://api.github.com/repos/whatpulse/linux-external-pcap-service/releases/latest'

if command -v dnf5 >/dev/null 2>&1; then
  DNF=dnf5
elif command -v dnf >/dev/null 2>&1; then
  DNF=dnf
else
  echo 'ERROR: dnf5/dnf is required in the build image.' >&2
  exit 1
fi

for cmd in curl sha256sum tar rpm install ldd python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: Missing required command: ${cmd}" >&2
    exit 1
  }
done

workdir="$(mktemp -d)"
trap 'rm -rf -- "$workdir"' EXIT

# Look up the latest stable release and get the digest for its SOURCE asset.
curl --fail --location --silent --show-error \
  --retry 3 --connect-timeout 15 --max-time 60 \
  --header 'Accept: application/vnd.github+json' \
  --output "$workdir/release.json" "$RELEASE_API"

python3 - "$workdir/release.json" > "$workdir/release-fields" <<'PYRELEASE'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    release = json.load(file)

tag = release.get("tag_name", "")
if not isinstance(tag, str) or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
    sys.exit("ERROR: Latest release has an unexpected version tag")

version = tag[1:]
filename = f"whatpulse-pcap-service-{version}-source.tar.gz"
assets = [asset for asset in release.get("assets", [])
          if asset.get("name") == filename and asset.get("state") == "uploaded"]
if len(assets) != 1:
    sys.exit(f"ERROR: Expected one source asset named {filename}")

asset = assets[0]
digest = asset.get("digest", "")
if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
    sys.exit("ERROR: The source asset is missing its GitHub SHA-256 digest")

url = asset.get("browser_download_url", "")
expected = ("https://github.com/whatpulse/linux-external-pcap-service/"
            f"releases/download/{tag}/{filename}")
if url != expected:
    sys.exit("ERROR: Unexpected source asset download URL")

print(version)
print(filename)
print(digest.partition(":")[2].lower())
print(url)
PYRELEASE

mapfile -t release_fields < "$workdir/release-fields"
VERSION="${release_fields[0]}"
ARCHIVE="${release_fields[1]}"
SOURCE_SHA256="${release_fields[2]}"
URL="${release_fields[3]}"

printf 'Downloading WhatPulse PCap Service %s...\n' "$VERSION"
curl --fail --location --silent --show-error \
  --retry 3 --connect-timeout 15 --max-time 180 \
  --output "$workdir/$ARCHIVE" "$URL"
printf '%s  %s\n' "$SOURCE_SHA256" "$workdir/$ARCHIVE" | sha256sum --check --status || {
  echo 'ERROR: Source archive SHA-256 mismatch.' >&2
  exit 1
}

# Install missing build tools only; keep existing image packages untouched.
build_deps=(gcc-c++ make libpcap-devel)
added_deps=()
for pkg in "${build_deps[@]}"; do
  if ! rpm --quiet -q "$pkg"; then
    added_deps+=("$pkg")
  fi
done
if (( ${#added_deps[@]} )); then
  "$DNF" -y install "${added_deps[@]}"
fi

mkdir -p "$workdir/src"
tar -xzf "$workdir/$ARCHIVE" -C "$workdir/src"
source_dir="$workdir/src"
if [[ ! -f "$source_dir/Makefile" ]]; then
  # Some upstream source archives contain a single top-level directory.
  shopt -s nullglob
  entries=("$source_dir"/*)
  shopt -u nullglob
  if (( ${#entries[@]} != 1 )) || [[ ! -f "${entries[0]}/Makefile" ]]; then
    echo 'ERROR: Unexpected source archive layout.' >&2
    exit 1
  fi
  source_dir="${entries[0]}"
fi
(
  cd "$source_dir"
  make -j"$(nproc)"
  ./whatpulse-pcap-service --version
)

install -D -o root -g root -m 0755 \
  "$source_dir/whatpulse-pcap-service" \
  /usr/bin/whatpulse-pcap-service
install -D -o root -g root -m 0644 \
  "$source_dir/LICENSE" \
  /usr/share/licenses/whatpulse-pcap-service/LICENSE

# The upstream application checks geteuid() == 0, so a non-root systemd
# User= is not supported without patching the C++ source. Drop almost all
# privileges and allow only the two network capabilities used upstream.
install -d -o root -g root -m 0755 /usr/lib/systemd/system
cat > /usr/lib/systemd/system/whatpulse-pcap-service.service <<'UNIT'
[Unit]
Description=WhatPulse External PCap Service by WhatPulse
Documentation=https://github.com/whatpulse/linux-external-pcap-service
After=network.target
Wants=network.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/bin/whatpulse-pcap-service --host 127.0.0.1 --log-file ""
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

NoNewPrivileges=yes
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectHostname=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
RestrictRealtime=yes
RestrictNamespaces=yes
RestrictSUIDSGID=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_PACKET AF_NETLINK
LockPersonality=yes
SystemCallArchitectures=native
UMask=0077

# The service only connects to the local WhatPulse client on TCP/3499.
IPAddressDeny=any
IPAddressAllow=localhost

[Install]
WantedBy=multi-user.target
UNIT

# Remove only toolchain packages that this script installed. This runs only
# during image creation, never on a booted Agate system.
if (( ${#added_deps[@]} )); then
  "$DNF" -y remove "${added_deps[@]}"
fi

# Check the final binary AFTER removal of build-only dependencies.
if ldd /usr/bin/whatpulse-pcap-service | grep -q 'not found'; then
  echo 'ERROR: The installed binary has missing runtime libraries.' >&2
  exit 1
fi
/usr/bin/whatpulse-pcap-service --version
printf '%s\n' 'WhatPulse PCap Service installed in /usr. Enable it with the BlueBuild systemd module.'
