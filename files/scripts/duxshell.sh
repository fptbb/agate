#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${SET_X:-}" ]]; then
    set -x
fi

log() {
    printf '=== %s ===\n' "$*"
}

fatal() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ ${EUID} -eq 0 ]] || fatal 'This BlueBuild script must run as root during image construction.'

log 'Configuring Dux Shell (DMS) and Niri for Agate...'

# This script runs during the BlueBuild image build. The installed DMS CLI in
# this COPR build blocks all `dms setup` subcommands on immutable systems, so
# the image build seeds version-matched upstream defaults without invoking DMS setup.
if [[ -e /run/ostree-booted ]]; then
    fatal 'Detected a booted ostree system. Run this through the BlueBuild script module while building the image, not on the installed system.'
fi

DMS_BIN="$(command -v dms || true)"
NIRI_BIN="$(command -v niri || true)"
SETPRIV_BIN="$(command -v setpriv || true)"
CURL_BIN="$(command -v curl || true)"
[[ -n "$DMS_BIN" ]] || fatal 'dms was not found; install the Dux Shell package before running this script.'
[[ -n "$NIRI_BIN" ]] || fatal 'niri was not found; install Niri before running this script.'
[[ -n "$SETPRIV_BIN" ]] || fatal 'setpriv was not found; install the Fedora util-linux package before running this script.'
[[ -n "$CURL_BIN" ]] || fatal 'curl was not found; it is required to fetch version-matched DMS default templates.'
id nobody >/dev/null 2>&1 || fatal 'The temporary nobody account is unavailable.'

# DMS 1.6.3 and other versions with the same immutable-system policy refuse
# every `dms setup` subcommand on Bazzite/Atomic systems, including in a build
# container. Fetch the default fragments from the matching upstream release
# tag instead. If the package version is not a semantic release version, fail
# rather than silently pairing DMS with templates from a different version.
DMS_VERSION="$(rpm -q --qf '%{VERSION}' dms 2>/dev/null || true)"
[[ -n "$DMS_VERSION" ]] || fatal 'Could not determine the installed DMS RPM version.'
[[ "$DMS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fatal "DMS version '$DMS_VERSION' is not a semantic release version; pin matching DMS templates explicitly before building."
DMS_TEMPLATE_TAG="v${DMS_VERSION}"
DMS_TEMPLATE_BASE_URL="https://raw.githubusercontent.com/duxlabs-dev/dux-shell/${DMS_TEMPLATE_TAG}/core/internal/config/embedded"

# Fedora's Niri RPM ships the same default config embedded in the niri binary
# as /usr/share/doc/niri/default-config.kdl. Use the installed package's copy
# so the starter config follows the Niri version in this image.
DEFAULT_NIRI_CONFIG=''
for candidate in \
    /usr/share/doc/niri/default-config.kdl \
    /usr/share/niri/default-config.kdl; do
    if [[ -s "$candidate" ]]; then
        DEFAULT_NIRI_CONFIG="$candidate"
        break
    fi
done
[[ -n "$DEFAULT_NIRI_CONFIG" ]] || fatal 'Could not find Niri default-config.kdl. Check that the installed Niri package includes its default configuration under /usr/share/doc/niri/.'

# Create an unprivileged temporary home for config validation. Do not invoke
# `dms setup`: the DMS CLI intentionally blocks all setup subcommands on
# image-based systems, even when run from a BlueBuild build container.
SEED_HOME="$(mktemp -d /tmp/agate-dms-seed.XXXXXX)"
cleanup() {
    rm -rf -- "$SEED_HOME"
}
trap cleanup EXIT
SEED_UID="$(id -u nobody)"
SEED_GID="$(id -g nobody)"
chown "$SEED_UID:$SEED_GID" "$SEED_HOME"

run_as_seed() {
    "$SETPRIV_BIN" \
        --reuid="$SEED_UID" \
        --regid="$SEED_GID" \
        --clear-groups \
        --inh-caps=-all \
        -- "$@"
}

SEED_NIRI_DIR="$SEED_HOME/.config/niri"
SEED_NIRI_CONFIG="$SEED_NIRI_DIR/config.kdl"
SEED_NIRI_DMS_DIR="$SEED_NIRI_DIR/dms"
DMS_NIRI_FRAGMENTS=(
    colors.kdl
    layout.kdl
    alttab.kdl
    binds.kdl
    outputs.kdl
    cursor.kdl
    windowrules.kdl
)
install -d -m 0755 -o "$SEED_UID" -g "$SEED_GID" "$SEED_NIRI_DMS_DIR"

log "Fetching DMS ${DMS_VERSION} Niri defaults from ${DMS_TEMPLATE_TAG}..."
for component in binds colors layout alttab; do
    template_url="${DMS_TEMPLATE_BASE_URL}/niri-${component}.kdl"
    "$CURL_BIN" --fail --silent --show-error --location \
        "$template_url" \
        --output "$SEED_NIRI_DMS_DIR/${component}.kdl" \
        || fatal "Failed to download DMS ${DMS_TEMPLATE_TAG} template: niri-${component}.kdl"
    [[ -s "$SEED_NIRI_DMS_DIR/${component}.kdl" ]] || fatal "Downloaded DMS template is empty: niri-${component}.kdl"
    chmod 0644 "$SEED_NIRI_DMS_DIR/${component}.kdl"
done

# DMS's Niri binds template uses this placeholder for the chosen terminal.
sed -i 's/{{TERMINAL_COMMAND}}/alacritty/g' "$SEED_NIRI_DMS_DIR/binds.kdl"
if grep -Fq '{{TERMINAL_COMMAND}}' "$SEED_NIRI_DMS_DIR/binds.kdl"; then
    fatal 'The DMS keybinding template still contains an unresolved terminal placeholder.'
fi

# DMS 1.6.3 has no separate embedded templates for these fragments. Create
# empty files because the generated Niri config includes all DMS-managed paths.
for component in outputs cursor windowrules; do
    : > "$SEED_NIRI_DMS_DIR/${component}.kdl"
    chmod 0644 "$SEED_NIRI_DMS_DIR/${component}.kdl"
done

[[ -d "$SEED_NIRI_DMS_DIR" ]] || fatal 'The DMS Niri template directory was not created.'
for fragment in "${DMS_NIRI_FRAGMENTS[@]}"; do
    # DMS 1.6.3 intentionally uses empty outputs, cursor and windowrules
    # placeholders; require these files to exist, not to contain content.
    [[ -f "$SEED_NIRI_DMS_DIR/$fragment" ]] || fatal "Missing DMS Niri template fragment: $fragment"
done
[[ -s "$SEED_NIRI_DMS_DIR/binds.kdl" ]] || fatal 'The DMS binds.kdl template is empty.'
[[ -s "$SEED_NIRI_DMS_DIR/colors.kdl" ]] || fatal 'The DMS colors.kdl template is empty.'
[[ -s "$SEED_NIRI_DMS_DIR/layout.kdl" ]] || fatal 'The DMS layout.kdl template is empty.'
[[ -s "$SEED_NIRI_DMS_DIR/alttab.kdl" ]] || fatal 'The DMS alttab.kdl template is empty.'

# DMS's fragments do not replace the main Niri config. Start from the default
# config shipped by this exact Niri package, then add
# DMS includes at the end (Niri merges included settings positionally).
if [[ ! -s "$SEED_NIRI_CONFIG" ]]; then
    install -d -m 0755 "$SEED_NIRI_DIR"
    install -m 0644 "$DEFAULT_NIRI_CONFIG" "$SEED_NIRI_CONFIG"
fi

# The upstream Niri example starts Waybar. DMS provides its own shell/panel,
# so remove only the stock Waybar autostart line to avoid showing two bars.
sed -i -E '/^[[:space:]]*spawn-at-startup[[:space:]]+"waybar"([[:space:]]|$)/d' "$SEED_NIRI_CONFIG"

ensure_dms_includes() {
    local config_file="$1"
    local fragment
    local missing=()

    for fragment in "${DMS_NIRI_FRAGMENTS[@]}"; do
        # Match both the ordinary include form and Niri's optional=true form.
        if ! grep -Eq "^[[:space:]]*include([[:space:]]+optional=true)?[[:space:]]+\"dms/${fragment}\"([[:space:]]|$)" "$config_file"; then
            missing+=("$fragment")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        {
            printf '\n// Agate: Dux Shell managed Niri configuration. Keep these includes last.\n'
            for fragment in "${missing[@]}"; do
                printf 'include "dms/%s"\n' "$fragment"
            done
        } >> "$config_file"
    fi
}

ensure_dms_includes "$SEED_NIRI_CONFIG"

log 'Validating the generated Niri config before adding it to /etc/skel...'
run_as_seed env \
    HOME="$SEED_HOME" \
    XDG_CONFIG_HOME="$SEED_HOME/.config" \
    "$NIRI_BIN" validate -c "$SEED_NIRI_CONFIG"

# Seed new accounts and also use this template later to fill missing files for
# existing accounts. cp -n preserves any image-maintainer-provided skeleton
# configs instead of overwriting them.
install -d -m 0755 /etc/skel/.config
cp -Rn "$SEED_HOME/.config/." /etc/skel/.config/

SKEL_NIRI_DIR='/etc/skel/.config/niri'
SKEL_NIRI_CONFIG="$SKEL_NIRI_DIR/config.kdl"
[[ -d "$SKEL_NIRI_DIR" ]] || fatal 'The Niri defaults were not copied into /etc/skel/.config/niri/.'
[[ -s "$SKEL_NIRI_CONFIG" ]] || fatal '/etc/skel/.config/niri/config.kdl is missing or empty.'

# Existing /etc/skel configuration belongs to the image maintainer. Preserve
# its settings, but ensure the DMS fragments are included and Waybar is not
# launched alongside DMS.
sed -i -E '/^[[:space:]]*spawn-at-startup[[:space:]]+"waybar"([[:space:]]|$)/d' "$SKEL_NIRI_CONFIG"
ensure_dms_includes "$SKEL_NIRI_CONFIG"

# Normalize the skeleton permissions before validating as an unprivileged
# user; generated template files must be readable by every future account.
chown -R root:root /etc/skel/.config/niri
find /etc/skel/.config/niri -type d -exec chmod 0755 {} +
find /etc/skel/.config/niri -type f -exec chmod 0644 {} +

# Check the final skeleton config too, so a pre-existing skeleton file cannot
# silently leave the image with broken Niri includes.
run_as_seed env \
    HOME=/etc/skel \
    XDG_CONFIG_HOME=/etc/skel/.config \
    "$NIRI_BIN" validate -c "$SKEL_NIRI_CONFIG"

log 'DMS/Niri defaults are available in /etc/skel/.config/niri/.'

# Link DMS and Dux Search to the systemd-managed Niri session. Fedora's Niri
# package supplies niri.service; fail early if the installed package is unlike
# the expected standalone-session package. After= orders startup, while PartOf=
# stops these services when niri.service stops (e.g. when switching to Plasma).
[[ -f /usr/lib/systemd/user/niri.service ]] || fatal 'The Niri systemd user unit was not found at /usr/lib/systemd/user/niri.service.'
mkdir -p /usr/lib/systemd/user/niri.service.wants
for service in dms dsearch; do
    unit="/usr/lib/systemd/user/${service}.service"
    [[ -f "$unit" ]] || fatal "Expected user service $unit was not installed by the Dux packages."

    ln -sfn "$unit" "/usr/lib/systemd/user/niri.service.wants/${service}.service"
    install -d -m 0755 "/usr/lib/systemd/user/${service}.service.d"
    cat > "/usr/lib/systemd/user/${service}.service.d/agate-niri-session.conf" <<'EOF_UNIT'
[Unit]
After=niri.service
PartOf=niri.service
EOF_UNIT
done

# Keep Niri's portal choices separate from Plasma. GTK handles general portals,
# KDE's portal is kept for the Secret interface (KWallet), and portal-wlr is
# selected only for ScreenCast and Screenshot. Leave RemoteDesktop unmapped
# because support depends on the installed portal backend/compositor combination.
install -d -m 0755 /usr/share/xdg-desktop-portal
cat > /usr/share/xdg-desktop-portal/niri-portals.conf <<'EOF_PORTALS'
[preferred]
default=gtk;
org.freedesktop.impl.portal.Secret=kde;
org.freedesktop.impl.portal.ScreenCast=wlr;
org.freedesktop.impl.portal.Screenshot=wlr;
EOF_PORTALS

log 'Niri portal preferences written to niri-portals.conf.'

# Launch Niri with only Niri-specific environment variables. Do not advertise
# this session as KDE or use KDE's menu prefix; Plasma keeps its own environment.
cat > /usr/bin/start-niri-agate <<'EOF_NIRI'
#!/usr/bin/env bash
set -euo pipefail

: "${HOME:?HOME must be set by the display manager}"

export XDG_CURRENT_DESKTOP=niri
export XDG_SESSION_DESKTOP=niri
export DESKTOP_SESSION=niri
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORMTHEME=qt6ct
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export XDG_MENU_PREFIX=plasma-

# Import the session environment before niri.service pulls in DMS and Dux
# Search, so user services start with the correct Wayland/desktop variables.
SESSION_ENV_VARS=(
    XDG_CURRENT_DESKTOP
    XDG_SESSION_DESKTOP
    DESKTOP_SESSION
    XDG_SESSION_TYPE
    QT_QPA_PLATFORMTHEME
    QT_WAYLAND_DISABLE_WINDOWDECORATION
)
for var in PAM_KWALLET5_LOGIN PAM_KWALLET_LOGIN; do
    if [[ -n "${!var-}" ]]; then
        SESSION_ENV_VARS+=("$var")
    fi
done

if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    if ! dbus-update-activation-environment --systemd "${SESSION_ENV_VARS[@]}"; then
        printf '%s\n' 'Agate: could not import all session variables before Niri starts; continuing and allowing Niri to import its environment.' >&2
    fi
else
    printf '%s\n' 'Agate: dbus-update-activation-environment is unavailable; Niri will import its own session environment.' >&2
fi

# Seed only the configs this integration owns for users created before this
# image. Do not copy unrelated /etc/skel settings into an existing account.
# cp -n preserves personal dotfiles; defaults are never forced over files.
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CONFIG_HOME
mkdir -p "$XDG_CONFIG_HOME"
for app_config in niri; do
    skeleton_config="/etc/skel/.config/$app_config"
    [[ -d "$skeleton_config" ]] || continue
    mkdir -p "$XDG_CONFIG_HOME/$app_config"
    cp -Rn "$skeleton_config/." "$XDG_CONFIG_HOME/$app_config/"
done

NIRI_CONFIG_DIR="$XDG_CONFIG_HOME/niri"
NIRI_CONFIG_FILE="$NIRI_CONFIG_DIR/config.kdl"
if [[ -f "$NIRI_CONFIG_FILE" ]] && ! grep -Fq 'dms/binds.kdl' "$NIRI_CONFIG_FILE"; then
    printf '%s\n' 'Agate: preserved your existing Niri config; add DMS include lines if you want DMS-managed keybinds/layout loaded.' >&2
fi

exec niri-session
EOF_NIRI
chmod 0755 /usr/bin/start-niri-agate

NIRI_DESKTOP='/usr/share/wayland-sessions/niri.desktop'
[[ -f "$NIRI_DESKTOP" ]] || fatal "Niri desktop entry was not found at $NIRI_DESKTOP."
grep -q '^Exec=' "$NIRI_DESKTOP" || fatal "$NIRI_DESKTOP has no Exec= line to update."
sed -i 's|^Exec=.*|Exec=/usr/bin/start-niri-agate|' "$NIRI_DESKTOP"
if grep -q '^TryExec=' "$NIRI_DESKTOP"; then
    sed -i 's|^TryExec=.*|TryExec=/usr/bin/start-niri-agate|' "$NIRI_DESKTOP"
fi

# Avoid editing vendor KDE autostart entries. Entries with KDE-only visibility
# should already be excluded by XDG_CURRENT_DESKTOP=niri; add narrow overrides
# only if testing identifies a specific app that incorrectly starts in Niri.

log 'DUX SHELL / NIRI CONFIG DONE.'
