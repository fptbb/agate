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
    printf "y\nn\n" | ./install.sh 3 12 2
    printf "y\nn\n" | ./install.sh 4 12 2
    printf "y\nn\n" | ./install.sh 1 12 2

# installs kora icons
agate-install-kora:
    #!/usr/bin/env bash
    set -e

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    # removes existing kora icons
    rm -rf ~/.local/share/icons/kora*

    echo "Fetching latest Kora release metadata..."
    # gets the tarball url from the latest release via github api
    TARBALL_URL=$(curl -s https://api.github.com/repos/bikass/kora/releases/latest | grep "tarball_url" | cut -d '"' -f 4)

    if [ -z "$TARBALL_URL" ]; then
        echo "Error: Could not find latest release URL."
        exit 1
    fi

    echo "Downloading and extracting Kora icons..."
    mkdir -p "$TMP_DIR/kora"
    # extracts directly into the temp folder, stripping the root archive directory
    curl -L "$TARBALL_URL" | tar -xz -C "$TMP_DIR/kora" --strip-components=1

    mkdir -p ~/.local/share/icons
    cp -r "$TMP_DIR"/kora/kora* ~/.local/share/icons/

    echo "Updating icon cache..."
    for dir in ~/.local/share/icons/kora*/; do
        if [ -d "$dir" ]; then
            gtk-update-icon-cache -q -f -t "$dir" || true
        fi
    done

    echo "Installation complete."

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
