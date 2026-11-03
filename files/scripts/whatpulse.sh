#!/usr/bin/env bash
# BlueBuild: files/scripts/whatpulse-pcap.sh
# Installs the latest stable upstream RPM. x86_64 only.
set -euo pipefail

[[ $(uname -m) == x86_64 ]] || { echo 'WhatPulse RPM requires x86_64.' >&2; exit 1; }

# Raw input access is independent of network capture; preserve Agate's setting.
WHATPULSE_ENABLE_INPUT_UACCESS="${WHATPULSE_ENABLE_INPUT_UACCESS:-1}"
[[ $WHATPULSE_ENABLE_INPUT_UACCESS =~ ^[01]$ ]] || {
  echo 'WHATPULSE_ENABLE_INPUT_UACCESS must be 0 or 1.' >&2; exit 1;
}

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# GitHub's latest endpoint skips prereleases. Match the RPM by package/arch,
# not by version: release tags and uploaded filenames can disagree.
curl -fsSL --retry 3 \
  https://api.github.com/repos/whatpulse/linux-external-pcap-service/releases/latest \
  -o "$tmp/release.json"

fields="$(jq -er '
  .tag_name as $tag
  | [.assets[] | select(
      .state == "uploaded"
      and (.name | test("^whatpulse-pcap-service-.+\\.x86_64\\.rpm$"))
      and (.browser_download_url == ("https://github.com/whatpulse/linux-external-pcap-service/releases/download/" + $tag + "/" + .name))
    )]
  | if length == 1 then .[0] else error("Expected exactly one x86_64 RPM") end
  | [.browser_download_url, .digest, $tag] | @tsv
' "$tmp/release.json")"
IFS=$'\t' read -r url digest tag <<< "$fields"
[[ $digest =~ ^sha256:[[:xdigit:]]{64}$ ]] || { echo 'Missing valid RPM SHA-256.' >&2; exit 1; }

curl -fsSL --retry 3 "$url" -o "$tmp/whatpulse.rpm"
printf '%s  %s\n' "${digest#sha256:}" "$tmp/whatpulse.rpm" | sha256sum -c -
dnf5 -y install "$tmp/whatpulse.rpm"

# The upstream RPM currently omits the license file.
curl -fsSL --retry 3 \
  "https://raw.githubusercontent.com/whatpulse/linux-external-pcap-service/${tag}/LICENSE" \
  -o "$tmp/LICENSE"
install -Dm644 "$tmp/LICENSE" /usr/share/licenses/whatpulse-pcap-service/LICENSE

# Optional raw keyboard/mouse access for the active local desktop session.
rule=/usr/share/whatpulse-pcap-service/70-whatpulse-input.rules
install -d "${rule%/*}"
cat > "$rule" <<'UDEV'
# Grants the active seat user raw input access (including keystrokes).
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event[0-9]*", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess"
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event[0-9]*", ENV{ID_INPUT_KEY}=="1", TAG+="uaccess"
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event[0-9]*", ENV{ID_INPUT_MOUSE}=="1", TAG+="uaccess"
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event[0-9]*", ENV{ID_INPUT_TOUCHPAD}=="1", TAG+="uaccess"
UDEV
chmod 0644 "$rule"
if [[ $WHATPULSE_ENABLE_INPUT_UACCESS == 1 ]]; then
  install -Dm644 "$rule" /usr/lib/udev/rules.d/70-whatpulse-input.rules
fi

# Keep upstream's systemd hardening; just log to journald instead of /var/log.
unit_dir=/usr/lib/systemd/system/whatpulse-pcap-service.service.d
install -d "$unit_dir"
cat > "$unit_dir/90-agate.conf" <<'UNIT'
[Service]
ExecStart=
ExecStart=/usr/bin/whatpulse-pcap-service --host 127.0.0.1 --log-file ""
UNIT

/usr/bin/whatpulse-pcap-service --version
