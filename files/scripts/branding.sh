#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

# Your code goes here.
IMAGE_INFO="/usr/share/ublue-os/image-info.json"
IMAGE_REF="ostree-image-signed:docker://quay.io/fptbb/agate"
IMAGE_TAG="latest"
IMAGE_BRANCH="latest"

# image-info File
sed -i 's/"image-name": [^,]*/"image-name": "'"agate"'"/' $IMAGE_INFO
sed -i 's/"image-vendor": [^,]*/"image-vendor": "'"fptbb"'"/' $IMAGE_INFO
sed -i 's|"image-tag": [^,]*|"image-tag": "'"$IMAGE_TAG"'"|' $IMAGE_INFO
sed -i 's|"image-branch": [^,]*|"image-branch": "'"$IMAGE_BRANCH"'"|' $IMAGE_INFO
sed -i 's|"version-pretty": "Stable (F\([^"]*\))"|"version-pretty": "Latest (F\1)"|' $IMAGE_INFO
sed -i 's|"image-ref": [^,]*|"image-ref": "'"$IMAGE_REF"'"|' $IMAGE_INFO

YAFTI_CONFIG="/usr/share/yafti/yafti.yml"

sed -i 's/^title: Bazzite Portal/title: System Utilities/' "$YAFTI_CONFIG"

sed -i '/^screens:/a\
  - title: "Agate Utilities"\
    description: "Agate-specific installers and maintenance tools"\
    actions:\
      - id: "agate-themes"\
        title: "Agate Themes"\
        description: "Installs Catppuccin, Kora, and PlasMusic."\
        default: false\
        script: "ujust agate-manage-themes"\
      - id: "agate-nixpkgs"\
        title: "Install Nix"\
        description: "Installs the Nix package manager."\
        default: false\
        script: "ujust agate-nixpkgs"\
      - id: "agate-devbox"\
        title: "Install DevBox"\
        description: "Installs DevBox for disposable development environments."\
        default: false\
        script: "ujust agate-devbox"\
      - id: "dotfiles-update"\
        title: "Update Dotfiles"\
        description: "Pulls dotfiles changes from the repo and applies them locally. This can overwrite or remove local files."\
        default: false\
        script: "ujust dotfiles-update"\
      - id: "dotfiles-apply"\
        title: "Apply Dotfiles"\
        description: "Applies the repo state to this system. This can overwrite or remove local files."\
        default: false\
        script: "ujust dotfiles-apply"\
      - id: "dotfiles-status"\
        title: "Dotfiles Status"\
        description: "Shows what files are currently changed before syncing or applying."\
        default: false\
        script: "ujust dotfiles-status"\
      - id: "dotfiles-diff"\
        title: "Dotfiles Diff"\
        description: "Shows the exact line-by-line changes before syncing or applying."\
        default: false\
        script: "ujust dotfiles-diff"\
      - id: "dotfiles-sync"\
        title: "Sync Dotfiles"\
        description: "Pushes local computer changes into the dotfiles repo. Check status and diff first to avoid syncing unwanted changes."\
        default: false\
        script: "ujust dotfiles-sync"\
      - id: "agate-gpg-reload"\
        title: "Reload GPG Stack"\
        description: "Restarts the smartcard and GPG services."\
        default: false\
        script: "ujust agate-gpg-reload"\
' "$YAFTI_CONFIG"


# Icon replacements
mkdir -p /usr/share/icons/hicolor/scalable/apps/
mkdir -p /usr/share/icons/hicolor/scalable/places/

# replaces default bazzite and distributor logos with custom logos
ln -sf /usr/share/pixmaps/fp-logo.svg /usr/share/icons/hicolor/scalable/apps/bazzite-logo-icon.svg
ln -sf /usr/share/pixmaps/fp-logo.svg /usr/share/icons/hicolor/scalable/places/bazzite-logo.svg
ln -sf /usr/share/pixmaps/fp-logo.svg /usr/share/icons/hicolor/scalable/places/distributor-logo.svg
ln -sf /usr/share/pixmaps/fp-logo.svg /usr/share/icons/hicolor/scalable/places/distributor-logo-steamdeck.svg

# links specific variant logos
ln -sf /usr/share/pixmaps/fp-logo-white.svg /usr/share/icons/hicolor/scalable/places/bazzite-logo-white.svg
ln -sf /usr/share/pixmaps/fp-logo-le.svg /usr/share/icons/hicolor/scalable/places/bazzite-logo-le.svg

# Remove Deck Mode session entries
rm -f /usr/share/wayland-sessions/gamescope-session.desktop
rm -f /usr/share/wayland-sessions/steam-plus.desktop
