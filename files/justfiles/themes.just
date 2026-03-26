# manages all theme components
agate-manage-themes: agate-install-catppuccin agate-install-kora agate-install-plasmusic
    @echo "Theme installation complete."

# installs catppuccin kde themes
agate-install-catppuccin:
    #!/usr/bin/env bash
    set -e

    TMP_DIR=$(mktemp -d)
    # fallback cleanup on failure
    trap 'rm -rf "$TMP_DIR"' EXIT

    # cleans up existing theme files to allow fresh installation and avoid directory conflicts
    rm -rf ~/.local/share/plasma/look-and-feel/Catppuccin-*
    rm -rf ~/.local/share/plasma/desktoptheme/Catppuccin-*
    rm -rf ~/.local/share/aurorae/themes/Catppuccin-*
    rm -rf ~/.local/share/color-schemes/Catppuccin-*
    rm -rf ~/.local/share/icons/Catppuccin-*
    rm -rf ~/.local/share/kpackage/generic/Catppuccin-*

    echo "Installing Catppuccin KDE themes..."
    git clone https://github.com/catppuccin/kde.git "$TMP_DIR/catppuccin-kde"
    cd "$TMP_DIR/catppuccin-kde"

    # answers yes to installation and no to applying the theme
    printf "y\nn\n" | ./install.sh 3 12 1
    printf "y\nn\n" | ./install.sh 4 12 1
    printf "y\nn\n" | ./install.sh 1 12 1

# installs kora icons
agate-install-kora:
    #!/usr/bin/env bash
    set -e

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    # removes existing kora icons
    rm -rf ~/.local/share/icons/kora*

    echo "Installing Kora icons..."
    git clone https://github.com/bikass/kora.git "$TMP_DIR/kora"
    mkdir -p ~/.local/share/icons
    cp -r "$TMP_DIR"/kora/kora* ~/.local/share/icons/

    echo "Updating icon cache..."
    # updates cache only for installed kora directories
    for dir in ~/.local/share/icons/kora*/; do
        if [ -d "$dir" ]; then
            gtk-update-icon-cache -q -f -t "$dir" || true
        fi
    done

# installs plasmusic toolbar
agate-install-plasmusic:
    #!/usr/bin/env bash
    set -e

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    echo "Installing PlasMusic Toolbar..."
    git clone https://github.com/ccatterina/plasmusic-toolbar.git "$TMP_DIR/plasmusic-toolbar"

    # removes existing installation to avoid conflict errors
    kpackagetool6 -t Plasma/Applet -r plasmusic-toolbar || true
    kpackagetool6 -t Plasma/Applet -i "$TMP_DIR/plasmusic-toolbar/src"
