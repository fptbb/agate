#!/usr/bin/env bash

# Tell this script to exit if there are any errors.
# You should have this in every custom script, to ensure that your completed
# builds actually ran successfully without any errors!
set -oue pipefail

# Your code goes here.
echo ' ---| Start Branding |--- '

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
IMAGE_REF="ostree-image-signed:docker://ghcr.io/fptbb/fp-os"

# image-info File
sed -i 's/"image-name": [^,]*/"image-name": "'"fp-os"'"/' $IMAGE_INFO
sed -i 's/"image-vendor": [^,]*/"image-vendor": "'"fptbb"'"/' $IMAGE_INFO
sed -i 's|"image-ref": [^,]*|"image-ref": "'"$IMAGE_REF"'"|' $IMAGE_INFO

# OS Release File
sed -i "s/^VARIANT_ID=.*/VARIANT_ID=fp-os/" /usr/lib/os-release
sed -i "s/^NAME=.*/NAME="'"Fp OS"'"/" /usr/lib/os-release
sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME="'"Fp OS"'"/" /usr/lib/os-release
sed -i "s/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="'"fp-pc"'"/" /usr/lib/os-release
sed -i "s/^HOME_URL=.*/HOME_URL="'"https:\/\/os.fpt.icu"'"/" /usr/lib/os-release
