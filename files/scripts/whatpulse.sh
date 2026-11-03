#!/usr/bin/env bash
# BlueBuild: files/scripts/whatpulse-pcap.sh (latest upstream RPM)
# Installs the upstream x86_64 RPM into the immutable /usr tree.
set -euo pipefail

if (( EUID != 0 )); then
  echo 'ERROR: This script must run as root during the BlueBuild image build.' >&2
  exit 1
fi

# Input monitoring is independent from the network PCap service.
# Set to 1 in PRIVATE builds that should grant the active desktop user access
# to raw keyboard and mouse events. For public images, leave disabled and let
# each machine opt in explicitly. This is a security-sensitive permission.
WHATPULSE_ENABLE_INPUT_UACCESS="${WHATPULSE_ENABLE_INPUT_UACCESS:-1}"
case "$WHATPULSE_ENABLE_INPUT_UACCESS" in
  0|1) ;;
  *) echo 'ERROR: WHATPULSE_ENABLE_INPUT_UACCESS must be 0 or 1.' >&2; exit 1 ;;
esac

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

for cmd in curl sha256sum rpm install ldd python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: Missing required command: ${cmd}" >&2
    exit 1
  }
done

workdir="$(mktemp -d)"
trap 'rm -rf -- "$workdir"' EXIT

# GitHub's /releases/latest endpoint excludes drafts and prereleases.
# Resolve exactly one x86_64 RPM for the release tag; never guess a URL.
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
if release.get("draft") or release.get("prerelease"):
    sys.exit("ERROR: The returned release is not stable")

version = tag[1:]
# Match the RPM's release number without relying on it always being '-1'.
# The package version itself must agree with the GitHub release tag.
rpm_pattern = re.compile(
    rf"whatpulse-pcap-service-{re.escape(version)}-[0-9]+"
    r"(?:\.[A-Za-z0-9_]+)*\.x86_64\.rpm"
)
assets = [
    asset for asset in release.get("assets", [])
    if isinstance(asset, dict)
    and isinstance(asset.get("name"), str)
    and rpm_pattern.fullmatch(asset["name"])
    and asset.get("state") == "uploaded"
]
if len(assets) != 1:
    sys.exit(f"ERROR: Expected exactly one x86_64 RPM for {tag}; found {len(assets)}")

asset = assets[0]
filename = asset["name"]
digest = asset.get("digest", "")
if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
    sys.exit("ERROR: The RPM asset is missing its GitHub SHA-256 digest")

url = asset.get("browser_download_url", "")
expected = (
    "https://github.com/whatpulse/linux-external-pcap-service/"
    f"releases/download/{tag}/{filename}"
)
if url != expected:
    sys.exit("ERROR: Unexpected RPM asset download URL")

print(tag)
print(version)
print(filename)
print(digest.partition(":")[2].lower())
print(url)
PYRELEASE

mapfile -t release_fields < "$workdir/release-fields"
TAG="${release_fields[0]}"
VERSION="${release_fields[1]}"
RPM_FILE="${release_fields[2]}"
RPM_SHA256="${release_fields[3]}"
URL="${release_fields[4]}"

# Upstream only publishes prebuilt x86_64 RPMs at present.
if [[ "$(rpm --eval '%{_arch}')" != x86_64 ]]; then
  echo 'ERROR: The upstream WhatPulse RPM is currently available only for x86_64.' >&2
  exit 1
fi

printf 'Downloading WhatPulse PCap Service %s (%s)...\n' "$VERSION" "$RPM_FILE"
curl --fail --location --silent --show-error \
  --retry 3 --connect-timeout 15 --max-time 180 \
  --output "$workdir/$RPM_FILE" "$URL"
printf '%s  %s\n' "$RPM_SHA256" "$workdir/$RPM_FILE" | sha256sum --check --status || {
  echo 'ERROR: RPM SHA-256 mismatch.' >&2
  exit 1
}

# Check the RPM header and its payload before running any package scripts.
metadata="$(rpm -qp --qf '%{NAME}|%{VERSION}|%{ARCH}' "$workdir/$RPM_FILE")"
IFS='|' read -r rpm_name rpm_version rpm_arch <<< "$metadata"
if [[ "$rpm_name" != 'whatpulse-pcap-service' || "$rpm_version" != "$VERSION" || "$rpm_arch" != x86_64 ]]; then
  echo "ERROR: Unexpected RPM package metadata: $metadata" >&2
  exit 1
fi
if ! rpm -qpl "$workdir/$RPM_FILE" | grep -Fx '/usr/bin/whatpulse-pcap-service' >/dev/null; then
  echo 'ERROR: RPM does not contain the expected /usr/bin/whatpulse-pcap-service.' >&2
  exit 1
fi

# DNF resolves runtime dependencies (including libpcap) without a C++ toolchain.
"$DNF" -y install "$workdir/$RPM_FILE"

# Upstream's RPM may not ship its license text; retain the original Agate copy.
if [[ ! -f /usr/share/licenses/whatpulse-pcap-service/LICENSE ]]; then
  curl --fail --location --silent --show-error \
    --retry 3 --connect-timeout 15 --max-time 60 \
    --output "$workdir/LICENSE" \
    "https://raw.githubusercontent.com/whatpulse/linux-external-pcap-service/${TAG}/LICENSE"
  if [[ ! -s "$workdir/LICENSE" ]]; then
    echo 'ERROR: Upstream LICENSE file is empty.' >&2
    exit 1
  fi
  install -D -o root -g root -m 0644 \
    "$workdir/LICENSE" \
    /usr/share/licenses/whatpulse-pcap-service/LICENSE
fi

# Ship an opt-in udev rule template in /usr. It is intentionally not active
# by default, because any process owned by the active seat user could read
# raw keystrokes once these ACLs are granted. Keep the rule before systemd's
# 73-seat-late.rules, which applies the uaccess ACL.
install -d -m 0755 /usr/share/whatpulse-pcap-service
cat > /usr/share/whatpulse-pcap-service/70-whatpulse-input.rules <<'UDEV'
# WhatPulse raw input access for active local sessions (systemd-logind).
# WARNING: grants access to *all* applications running as that user.
# Avoid MODE="0666", GROUP="input", and chmod on /dev/input/event*.
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event[0-9]*", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess"
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event[0-9]*", ENV{ID_INPUT_KEY}=="1", TAG+="uaccess"
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event[0-9]*", ENV{ID_INPUT_MOUSE}=="1", TAG+="uaccess"
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event[0-9]*", ENV{ID_INPUT_TOUCHPAD}=="1", TAG+="uaccess"
UDEV
chmod 0644 /usr/share/whatpulse-pcap-service/70-whatpulse-input.rules
if [[ "$WHATPULSE_ENABLE_INPUT_UACCESS" == 1 ]]; then
  install -D -m 0644 \
    /usr/share/whatpulse-pcap-service/70-whatpulse-input.rules \
    /usr/lib/udev/rules.d/70-whatpulse-input.rules
  echo 'WARNING: Enabled active-seat access to raw keyboard and mouse devices.' >&2
else
  echo 'WhatPulse input monitoring: udev rule available, opt-in required.'
fi

# Keep the RPM-owned unit intact. Override its settings from /usr so that
# Agate retains its stricter sandboxing without modifying an RPM-owned file.
# Upstream requires EUID 0; bounding capabilities still reduces privileges.
install -d -o root -g root -m 0755 \
  /usr/lib/systemd/system/whatpulse-pcap-service.service.d
cat > /usr/lib/systemd/system/whatpulse-pcap-service.service.d/90-agate-hardening.conf <<'UNIT'
[Unit]
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
ExecStart=
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
UNIT
chmod 0644 /usr/lib/systemd/system/whatpulse-pcap-service.service.d/90-agate-hardening.conf

# Verify all required shared libraries are available in the final image.
if ldd /usr/bin/whatpulse-pcap-service | grep -F 'not found' >/dev/null; then
  echo 'ERROR: The installed binary has missing runtime libraries.' >&2
  exit 1
fi
/usr/bin/whatpulse-pcap-service --version
printf '%s\n' 'WhatPulse PCap Service RPM installed; Agate hardening drop-in is present. Manage enablement with the BlueBuild systemd module.'
if [[ "$WHATPULSE_ENABLE_INPUT_UACCESS" == 0 ]]; then
  printf '%s\n' 'To enable input access on a booted machine: sudo install -Dm644 /usr/share/whatpulse-pcap-service/70-whatpulse-input.rules /etc/udev/rules.d/70-whatpulse-input.rules'
fi
