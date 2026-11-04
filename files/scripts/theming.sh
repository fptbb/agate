#!/usr/bin/env bash
set ${SET_X:+-x} -eou pipefail
trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG
log() {
    echo "=== $* ==="
}

#!/usr/bin/env bash

log "Removing default wallpapers and setting up symlinks for default wallpapers."

base_dir="/usr/share/wallpapers/"

wallpapers=(
    "giants.jxl"
    "Steam Deck Logo 1.jpg"
    "Steam Deck Logo 2.jpg"
    "Steam Deck Logo 3.jpg"
    "Steam Deck Logo 4.jpg"
    "Steam Deck Logo 5.jpg"
    "Steam Deck Logo 6.jpg"
    "Steam Deck Logo 7.jpg"
    "Steam Deck Logo 8.jpg"
    "Steam Deck Logo 9.jpg"
    "Steam Deck Logo 10.jpg"
    "Steam Deck Logo 11.jpg"
    "Steam Deck Logo 12.jpg"
    "Steam Deck Logo 13.jpg"
    "Steam Deck Logo Default.jpg"
    "Troll.jpg"
    "ublue.png"
    "VGUI2.jpg"
)

rm -f "${wallpapers[@]/#/$base_dir}"

ln -sf /usr/share/wallpapers/Fox1/contents/images/2560x1080.jxl /usr/share/backgrounds/default.jxl
ln -sf /usr/share/wallpapers/Fox1/contents/images_dark/2560x1080.jxl /usr/share/backgrounds/default-dark.jxl
ln -sf /usr/share/wallpapers/Fox1/contents/images_dark/2560x1080.jxl /usr/share/wallpapers/convergence.jxl
ln -sf /usr/share/wallpapers/fox.png /usr/share/wallpapers/convergence.png


# -------------------------
# Default Plasma wallpaper
# -------------------------

log "Configuring Fox1 as the default Plasma wallpaper"

WALLPAPER="/usr/share/wallpapers/Fox1"
LOOK_AND_FEEL="/usr/share/plasma/look-and-feel"

if [[ ! -f "${WALLPAPER}/metadata.json" ]]; then
    log "Fox1 wallpaper package not found"
    exit 1
fi

for defaults in "${LOOK_AND_FEEL}"/*/contents/defaults; do
    [[ -f "$defaults" ]] || continue

    kwriteconfig6 \
        --file "$defaults" \
        --group Wallpaper \
        --key Image \
        Fox1

    log "Configured: $(basename "$(dirname "$(dirname "$(dirname "$defaults")")")")"
done