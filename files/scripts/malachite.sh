#!/usr/bin/env bash
set -euo pipefail
[[ -z "${SET_X:-}" ]] || set -x

# Build-time metadata is optional: a blocked Pages endpoint must not break Agate.
URL="${MALACHITE_INDEX_URL:-https://malachite.fpt.icu/images.json}"
CONFIG="${MALACHITE_CONFIG:-/usr/share/agate/malachite.json}"
APP_DIR="${MALACHITE_APPLICATIONS_DIR:-/usr/share/applications}"
TMPFILES="${MALACHITE_TMPFILES_PATH:-/usr/lib/tmpfiles.d/agate.conf}"

validate_index() {
    jq -e '
        (.images | type == "object" and length > 0)
        and (.images | to_entries | all(.[];
            (.key | test("^[a-z0-9][a-z0-9_-]*$"))
            and (.value.title | type == "string")
            and (.value.manager | type == "string")
            and (.value.reference | type == "string")
            and (.value.assemble | type == "string")
        ))
    ' "$1" >/dev/null 2>&1
}

install -d -m 0755 "$(dirname "$CONFIG")" "$APP_DIR" "$(dirname "$TMPFILES")"
tmp="$(mktemp "${CONFIG}.tmp.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT

echo "Fetching Malachite image index..."
if curl -fsSL --connect-timeout 10 --max-time 30 --retry 2 "$URL" -o "$tmp" && validate_index "$tmp"; then
    chmod 0644 "$tmp"
    mv -f -- "$tmp" "$CONFIG"
    echo "Using current Malachite index."
elif [[ -f "$CONFIG" ]] && validate_index "$CONFIG"; then
    echo "WARNING: Malachite index unavailable; using existing bundled copy." >&2
else
    echo "WARNING: Malachite index unavailable; using built-in known images." >&2
    # Offline snapshot from fpsys/malachite's 2026-11-13 manifest.
    # Update this snapshot when adding a new Malachite distribution.
    cat > "$tmp" <<'JSON'
{
  "registry": "quay.io", "namespace": "fpsys", "image_name": "malachite",
  "images": {
    "fedora": {
      "id": "fedora", "title": "Fedora", "summary": "A fedora based toolbox image.",
      "manager": "dnf", "reference": "quay.io/fpsys/malachite:fedora",
      "base": "quay.io/fedora/fedora-toolbox:latest", "assemble": "fedora.ini", "packages": ""
    },
    "alpine": {
      "id": "alpine", "title": "Alpine", "summary": "A cloud-native terminal experience",
      "manager": "apk", "reference": "quay.io/fpsys/malachite:alpine",
      "base": "quay.io/toolbx-images/alpine-toolbox:edge", "assemble": "alpine.ini", "packages": ""
    },
    "ubuntu": {
      "id": "ubuntu", "title": "Ubuntu", "summary": "An ubuntu based toolbox image.",
      "manager": "apt", "reference": "quay.io/fpsys/malachite:ubuntu",
      "base": "quay.io/toolbx/ubuntu-toolbox:latest", "assemble": "ubuntu.ini", "packages": ""
    },
    "almalinux": {
      "id": "almalinux", "title": "AlmaLinux", "summary": "An almalinux based toolbox image.",
      "manager": "dnf", "reference": "quay.io/fpsys/malachite:almalinux",
      "base": "quay.io/toolbx-images/almalinux-toolbox:10", "assemble": "almalinux.ini", "packages": ""
    }
  }
}
JSON
    validate_index "$tmp" || { echo "ERROR: built-in index is invalid" >&2; exit 1; }
    chmod 0644 "$tmp"
    mv -f -- "$tmp" "$CONFIG"
fi

mapfile -t images < <(jq -r '.images | keys[]' "$CONFIG")
echo "Generating ${#images[@]} Malachite desktop launchers..."

for name in "${images[@]}"; do
    [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || {
        echo "WARNING: invalid image ID: $name" >&2
        continue
    }
    pretty="$(jq -r --arg n "$name" '.images[$n].title // $n' "$CONFIG" | tr '\r\n' '  ')"
    cat > "${APP_DIR}/malachite-${name}.desktop" <<DESK
[Desktop Entry]
Name=Malachite ${pretty}
Comment=Enter the ${pretty}-based Malachite distrobox
Exec=distrobox enter ${name}
Icon=utilities-terminal
Type=Application
Categories=Development;System;TerminalEmulator;
Terminal=true
Actions=Update;Setup;Remove;

[Desktop Action Update]
Name=Update Container
Exec=ujust agate-malachite update ${name}
Terminal=true

[Desktop Action Setup]
Name=Setup / Replace
Exec=ujust agate-malachite apply ${name}
Terminal=true

[Desktop Action Remove]
Name=Remove Container
Exec=ujust agate-malachite purge ${name}
Terminal=true
DESK
    echo "Generated malachite-${name}.desktop"
done

cat > "$TMPFILES" <<'TMP'
# Create persistent directory for Agate system data
# Type Path Mode User Group Age Argument
d /var/lib/agate 0777 root root - -
TMP

echo "Malachite setup complete."
