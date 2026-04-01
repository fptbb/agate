#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

# Your code goes here.
IMAGE_INFO="/usr/share/ublue-os/image-info.json"
IMAGE_REF="ostree-image-signed:docker://quay.io/fptbb/agate"

# image-info File
sed -i 's/"image-name": [^,]*/"image-name": "'"agate"'"/' $IMAGE_INFO
sed -i 's/"image-vendor": [^,]*/"image-vendor": "'"fptbb"'"/' $IMAGE_INFO
sed -i 's|"image-ref": [^,]*|"image-ref": "'"$IMAGE_REF"'"|' $IMAGE_INFO


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