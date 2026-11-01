set lazy

# manages all theme components
agate-manage-themes: agate-install-catppuccin agate-install-kora agate-install-plasmusic
    @echo "Theme installation complete."

# installs catppuccin kde themes
agate-install-catppuccin:
    #!/usr/bin/env bash
    set -e

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    rm -rf ~/.local/share/plasma/look-and-feel/Catppuccin-*
    rm -rf ~/.local/share/plasma/desktoptheme/Catppuccin-*
    rm -rf ~/.local/share/aurorae/themes/Catppuccin-*
    rm -rf ~/.local/share/color-schemes/Catppuccin-*
    rm -rf ~/.local/share/icons/Catppuccin-*
    rm -rf ~/.local/share/kpackage/generic/Catppuccin-*

    echo "Cloning Catppuccin KDE repository..."
    git clone -q https://github.com/catppuccin/kde.git "$TMP_DIR/catppuccin-kde"
    cd "$TMP_DIR/catppuccin-kde"

    install_theme() {
        local theme_name="$1"
        shift
        echo -n "Installing $theme_name... "
        if env TERM=dumb printf "y\nn\n" | ./install.sh "$@" > "$TMP_DIR/install.log" 2>&1; then
            echo "OK"
        else
            echo "FAILED"
            echo "--- error log ---"
            cat -v "$TMP_DIR/install.log"
            exit 1
        fi
    }

    install_theme "Frappé Sapphire" 3 12 2
    install_theme "Latte Sapphire"  4 12 2
    install_theme "Mocha Sapphire"  1 12 2

# installs kora icons
agate-install-kora:
    #!/usr/bin/env bash
    set -e

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    rm -rf ~/.local/share/icons/kora*

    echo -n "Fetching latest Kora release metadata... "
    TARBALL_URL=$(curl -s https://api.github.com/repos/bikass/kora/releases/latest | grep "tarball_url" | cut -d '"' -f 4)

    if [ -z "$TARBALL_URL" ]; then
        echo "FAILED (Could not find latest release URL.)"
        exit 1
    fi
    echo "OK"

    echo -n "Downloading and extracting Kora icons... "
    mkdir -p "$TMP_DIR/kora"
    # extracts directly into the temp folder, stripping the root archive directory
    # using bash -c with pipefail to catch curl errors as well
    if bash -c 'set -o pipefail; curl -sSL "$1" 2>"$2/kora_curl.log" | tar -xz -C "$2/kora" --strip-components=1 >"$2/kora_tar.log" 2>&1' _ "$TARBALL_URL" "$TMP_DIR"; then
        echo "OK"
    else
        echo "FAILED"
        echo "--- curl error log ---"
        cat -v "$TMP_DIR/kora_curl.log"
        echo "--- tar error log ---"
        cat -v "$TMP_DIR/kora_tar.log"
        exit 1
    fi

    echo -n "Installing to ~/.local/share/icons... "
    mkdir -p ~/.local/share/icons
    cp -r "$TMP_DIR"/kora/kora* ~/.local/share/icons/
    echo "OK"

    echo -n "Updating icon cache... "
    for dir in ~/.local/share/icons/kora*/; do
        if [ -d "$dir" ]; then
            gtk-update-icon-cache -q -f -t "$dir" >/dev/null 2>&1 || true
        fi
    done
    echo "OK"

# installs plasmusic toolbar
agate-install-plasmusic:
    #!/usr/bin/env bash
    set -e

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    echo -n "Cloning PlasMusic Toolbar repository... "
    if git clone -q https://github.com/ccatterina/plasmusic-toolbar.git "$TMP_DIR/plasmusic-toolbar" >"$TMP_DIR/plasmusic_git.log" 2>&1; then
        echo "OK"
    else
        echo "FAILED"
        echo "--- error log ---"
        cat -v "$TMP_DIR/plasmusic_git.log"
        exit 1
    fi

    echo -n "Installing PlasMusic Toolbar... "
    kpackagetool6 -t Plasma/Applet -r plasmusic-toolbar >/dev/null 2>&1 || true
    if kpackagetool6 -t Plasma/Applet -i "$TMP_DIR/plasmusic-toolbar/src" >"$TMP_DIR/plasmusic_pkg.log" 2>&1; then
        echo "OK"
    else
        echo "FAILED"
        echo "--- error log ---"
        cat -v "$TMP_DIR/plasmusic_pkg.log"
        exit 1
    fi

# Fixes permissions, installs dependencies if missing, and updates Spicetify
[group("utilities")]
agate-spicetify:
    #!/usr/bin/bash
    set -e

    if ! command -v spicetify &> /dev/null; then
        read -p "Install spicetify-cli via Homebrew? (y/n) " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] && brew install spicetify-cli || exit 1
    fi

    if ! flatpak list | grep -q com.spotify.Client; then
        read -p "Install Spotify via Flathub? (y/n) " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] && flatpak install flathub com.spotify.Client -y || exit 1
    fi

    SYSTEM_PATH="/var/lib/flatpak/app/com.spotify.Client/x86_64/stable/active/files/extra/share/spotify"
    USER_PATH="$HOME/.local/share/flatpak/app/com.spotify.Client/x86_64/stable/active/files/extra/share/spotify"

    if [ -d "$SYSTEM_PATH" ]; then
        SPOTIFY_PATH="$SYSTEM_PATH"
        USE_SUDO=true
    elif [ -d "$USER_PATH" ]; then
        SPOTIFY_PATH="$USER_PATH"
        USE_SUDO=false
    else
        echo "Spotify Flatpak path not found." && exit 1
    fi

    mkdir -p "$SPOTIFY_PATH/Apps"

    if [ "$USE_SUDO" = true ]; then
        sudo chmod a+wr "$SPOTIFY_PATH"
        sudo chmod a+wr -R "$SPOTIFY_PATH/Apps"
    else
        chmod a+wr "$SPOTIFY_PATH"
        chmod a+wr -R "$SPOTIFY_PATH/Apps"
    fi

    spicetify config spotify_path "$SPOTIFY_PATH"

    FLATPAK_PREFS="$HOME/.var/app/com.spotify.Client/config/spotify/prefs"
    LEGACY_PREFS="$HOME/.config/spotify/prefs"

    if [ -f "$FLATPAK_PREFS" ]; then
        spicetify config prefs_path "$FLATPAK_PREFS"
    elif [ -f "$LEGACY_PREFS" ]; then
        spicetify config prefs_path "$LEGACY_PREFS"
    else
        spicetify config prefs_path "$FLATPAK_PREFS"
    fi

    spicetify update
    spicetify restore backup apply
    curl -fsSL https://raw.githubusercontent.com/spicetify/spicetify-marketplace/main/resources/install.sh | sh
