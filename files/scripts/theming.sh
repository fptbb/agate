#!/usr/bin/env bash
# System-wide KDE theming for Agate's BlueBuild image.
# Installs Catppuccin Frappe/Latte/Mocha Sapphire, Kora and PlasMusic.
# Defaults: Catppuccin Mocha Sapphire + Kora + Fox1 wallpaper.
set -Eeuo pipefail

log() { printf '=== %s ===\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die 'Run as root (BlueBuild script module).'
for cmd in git curl find kwriteconfig6 kpackagetool6 python3; do
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required build command: $cmd"
done

# Optional fixed refs make CI builds reproducible. Defaults track upstream.
CATPPUCCIN_REF="${CATPPUCCIN_REF:-main}"
KORA_REF="${KORA_REF:-master}"
PLASMUSIC_REF="${PLASMUSIC_REF:-main}"
CATPPUCCIN_CURSORS_VERSION="${CATPPUCCIN_CURSORS_VERSION:-v2.0.0}"

work="$(mktemp -d /tmp/agate-themes.XXXXXXXX)"
trap 'rm -rf -- "$work"' EXIT
stage="$work/stage"
mkdir -p "$stage" "$work/home" "$work/config" "$work/cache" "$work/runtime"
chmod 700 "$work/runtime"

clone() {
    local url="$1" ref="$2" destination="$3"
    git clone --quiet --depth=1 --single-branch --branch "$ref" "$url" "$destination"
    log "Fetched $(basename "$destination") at $(git -C "$destination" rev-parse --short=12 HEAD)"
}

# -------------------------
# Agate assets (moving branch, single sparse checkout)
# -------------------------

# Wallpapers and pixmaps are installed before wallpaper configuration below;
# branding.sh runs later in the recipe and consumes the installed pixmaps.
# Do not pin the assets branch. Record the actual commit in the CI output.
AGATE_ASSETS_REF="${AGATE_ASSETS_REF:-assets}"
assets_checkout="$work/agate-assets"
log "Fetching Agate assets branch: $AGATE_ASSETS_REF"
git clone --quiet \
    --depth 1 \
    --single-branch \
    --branch "$AGATE_ASSETS_REF" \
    --sparse \
    https://gitlab.com/fpsys/agate.git \
    "$assets_checkout"
git -C "$assets_checkout" sparse-checkout set \
    system/pointers system/wallpapers system/pixmaps system/anaconda
log "Fetched Agate assets at $(git -C "$assets_checkout" rev-parse HEAD)"

assets_dir="$assets_checkout/system"
for folder in pointers wallpapers pixmaps; do
    [[ -d "$assets_dir/$folder" ]] || die "Missing Agate assets directory: $folder"
done

# Drop inherited top-level wallpaper images and links, while keeping any
# wallpaper packages (subdirectories) provided by the base image.
# Copy our wallpapers AFTER cleanup so every filename in assets is preserved.
install -d /usr/share/wallpapers /usr/share/pixmaps /usr/share/icons
find /usr/share/wallpapers -mindepth 1 -maxdepth 1 \
    \( -type f -o -type l \) -delete

for folder in wallpapers pixmaps; do
    cp -a "$assets_dir/$folder/." "/usr/share/$folder/"
    log "Installed Agate assets: $folder"
done

log 'Installing Agate Anaconda artwork'
anaconda_source="$assets_checkout/system/anaconda"
anaconda_dest="/usr/share/anaconda/pixmaps"

[[ -d "$anaconda_source" ]] || die "Missing Anaconda assets: $anaconda_source"

install -d "$anaconda_dest"
cp -a "$anaconda_source/." "$anaconda_dest/"
log 'Agate Anaconda artwork installed'

# Install all custom cursor packages, including names containing spaces.
# Replace existing copies rather than layering stale files over old themes.
cursors_source="$assets_dir/pointers"
[[ -d "$cursors_source" ]] || die "Cursor themes directory not found: $cursors_source"
shopt -s nullglob
cursor_themes=("$cursors_source"/*/)
shopt -u nullglob
(( ${#cursor_themes[@]} > 0 )) || die "No cursor themes found in $cursors_source"
for theme in "${cursor_themes[@]}"; do
    [[ -d "$theme/cursors" ]] || die "Invalid cursor package (no cursors/): $theme"
    name="$(basename "$theme")"
    dest="/usr/share/icons/$name"
    rm -rf -- "$dest"
    install -d "$dest"
    cp -a "$theme/." "$dest/"
    log "Installed cursor theme: $name"
done

# Run upstream Catppuccin's *build-only* modes in isolated XDG paths.
# Do not run 'auto': that mode applies the theme to the current user/session.
catppuccin_build() {
    (
        cd "$work/catppuccin-kde"
        HOME="$work/home" \
        XDG_DATA_HOME="$stage" \
        XDG_CONFIG_HOME="$work/config" \
        XDG_CACHE_HOME="$work/cache" \
        XDG_RUNTIME_DIR="$work/runtime" \
        QT_QPA_PLATFORM=offscreen \
        ./install.sh -q --local-cursor "$3" "$1" 12 2 "$2"
    )
}

log 'Cloning Catppuccin KDE'
clone https://github.com/catppuccin/kde.git "$CATPPUCCIN_REF" "$work/catppuccin-kde"

# Same choices as the old ujust command: Frappe (3), Latte (4), Mocha (1),
# Sapphire (12), Classic window decorations (2).
for item in '3:Frappe:frappe' '4:Latte:latte' '1:Mocha:mocha'; do
    IFS=: read -r choice name lowercase <<< "$item"
    theme="Catppuccin-${name}-Sapphire"
    accent_cursor="catppuccin-${lowercase}-sapphire-cursors"
    dark_cursor="catppuccin-${lowercase}-dark-cursors"
    log "Building $theme"

    # The generated Global Theme references a cursor ID. Download both cursor
    # variants explicitly with curl, avoiding a permanent wget dependency.
    mkdir -p "$stage/icons"
    for cursor in "$accent_cursor" "$dark_cursor"; do
        zipfile="$work/${cursor}.zip"
        curl --fail --location --silent --show-error --retry 3 \
            --output "$zipfile" \
            "https://github.com/catppuccin/cursors/releases/download/${CATPPUCCIN_CURSORS_VERSION}/${cursor}.zip"
        python3 -m zipfile -e "$zipfile" "$stage/icons"
        [[ -f "$stage/icons/$cursor/index.theme" || -f "$stage/icons/$cursor/cursor.theme" ]] \
            || die "Cursor archive lacks theme metadata: $cursor"
    done

    # These modes do not apply a running user theme. Global mode uses
    # kpackagetool6 to install *inside the temporary XDG_DATA_HOME*.
    catppuccin_build "$choice" global "$stage/icons/$accent_cursor"
    catppuccin_build "$choice" aurorae "$stage/icons/$accent_cursor"
    catppuccin_build "$choice" color "$stage/icons/$accent_cursor"

    # 'color' is generation-only: copy the generated .colors into stage.
    install -Dm644 \
        "$work/catppuccin-kde/dist/Catppuccin${name}Sapphire.colors" \
        "$stage/color-schemes/Catppuccin${name}Sapphire.colors"

    defaults="$stage/plasma/look-and-feel/$theme/contents/defaults"
    [[ -f "$defaults" ]] || die "Global Theme not staged: $theme (check kpackagetool6/XDG_DATA_HOME)"
    [[ -d "$stage/aurorae/themes/Catppuccin${name}-Classic" ]] \
        || die "Aurorae decoration not staged: $name"
    # The upstream theme otherwise sets its own icon theme, if present.
    kwriteconfig6 --file "$defaults" --group kdeglobals --group Icons --key Theme kora
    kwriteconfig6 --file "$defaults" --group Wallpaper --key Image Fox1
    log "Staged $theme"
done

log 'Installing Catppuccin assets system-wide'
for dir in plasma/look-and-feel aurorae/themes color-schemes icons; do
    install -d "/usr/share/$dir"
    cp -a "$stage/$dir/." "/usr/share/$dir/"
done

log 'Cloning and installing Kora icon themes'
clone https://github.com/bikass/kora.git "$KORA_REF" "$work/kora"
[[ -f "$work/kora/kora/index.theme" ]] || die 'Kora index.theme missing'
for variant in kora kora-pgrey; do
    if [[ -d "$work/kora/$variant" ]]; then
        rm -rf -- "/usr/share/icons/$variant"
        cp -a "$work/kora/$variant" "/usr/share/icons/$variant"
        if command -v gtk-update-icon-cache >/dev/null 2>&1; then
            gtk-update-icon-cache --force --quiet "/usr/share/icons/$variant" || true
        fi
        log "Installed icon theme: $variant"
    fi
done

log 'Cloning and installing PlasMusic Toolbar'
clone https://github.com/ccatterina/plasmusic-toolbar.git "$PLASMUSIC_REF" "$work/plasmusic-toolbar"
plasmusic_src="$work/plasmusic-toolbar/src"
[[ -f "$plasmusic_src/metadata.json" ]] || die 'PlasMusic metadata.json missing'
plugin_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Id"])' "$plasmusic_src/metadata.json")"
[[ "$plugin_id" == 'plasmusic-toolbar' ]] || die "Unexpected PlasMusic plugin ID: $plugin_id"
# A system-wide plasmoid is a KPackage directly under /usr/share/plasma/plasmoids/.
# Copying avoids installing into the build user's home directory.
install -d /usr/share/plasma/plasmoids
rm -rf -- "/usr/share/plasma/plasmoids/$plugin_id"
cp -a "$plasmusic_src" "/usr/share/plasma/plasmoids/$plugin_id"

log 'Configuring Agate wallpaper packages and desktop defaults'
# Fix metadata only for wallpapers supplied by Agate, not base-image packages.
for package in "$assets_dir/wallpapers"/*/; do
    [[ -f "$package/metadata.json" ]] || continue
    name="$(basename "$package")"
    python3 - "/usr/share/wallpapers/$name/metadata.json" "$name" <<'PYMETA'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
name = sys.argv[2]
data = json.loads(path.read_text(encoding='utf-8'))
if data['KPlugin'].get('Id') != name:
    data['KPlugin']['Id'] = name
    path.write_text(json.dumps(data, ensure_ascii=False, indent=4) + '\n', encoding='utf-8')
PYMETA
done

# Fox1 is the explicit default; verify its light and dark assets exist.
for mode in images images_dark; do
    [[ -s "/usr/share/wallpapers/Fox1/contents/$mode/2560x1080.jxl" ]] || \
        die "Missing Fox1 wallpaper variant: $mode"
done

install -d /usr/share/backgrounds
ln -sfn /usr/share/wallpapers/Fox1/contents/images/2560x1080.jxl \
    /usr/share/backgrounds/default.jxl
ln -sfn /usr/share/wallpapers/Fox1/contents/images_dark/2560x1080.jxl \
    /usr/share/backgrounds/default-dark.jxl

# Update every *installed* Global Theme, including the just-installed Catppuccin
# packages. This ensures Fox1 stays the default when switching Global Themes.
for defaults in /usr/share/plasma/look-and-feel/*/contents/defaults; do
    [[ -f "$defaults" ]] || continue
    kwriteconfig6 --file "$defaults" --group Wallpaper --key Image Fox1
done

# System defaults for *new profiles*. Existing per-user KConfig entries win.
install -d /etc/xdg
kwriteconfig6 --file /etc/xdg/kdeglobals \
    --group KDE --key LookAndFeelPackage Catppuccin-Mocha-Sapphire
kwriteconfig6 --file /etc/xdg/kdeglobals \
    --group General --key ColorScheme CatppuccinMochaSapphire
kwriteconfig6 --file /etc/xdg/kdeglobals \
    --group Icons --key Theme kora
kwriteconfig6 --file /etc/xdg/kcminputrc \
    --group Mouse --key cursorTheme catppuccin-mocha-sapphire-cursors

log 'Agate theming complete: Mocha Sapphire + Kora + Fox1; Frappe/Latte, PlasMusic and assets installed'
