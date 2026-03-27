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

    echo "Cloning Catppuccin KDE repository..."
    git clone -q https://github.com/catppuccin/kde.git "$TMP_DIR/catppuccin-kde"
    cd "$TMP_DIR/catppuccin-kde"

    install_theme() {
        local theme_name="$1"
        shift
        echo -n "Installing $theme_name... "
        # Run the prompt inputs and hide the installer's verbose output and clear commands
        if env TERM=dumb printf "y\nn\n" | ./install.sh "$@" > "$TMP_DIR/install.log" 2>&1; then
            echo "OK"
        else
            echo "FAILED"
            echo "--- error log ---"
            # Extract printable characters to avoid applying any raw escape sequences (like clear console)
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

    # removes existing kora icons
    rm -rf ~/.local/share/icons/kora*

    echo -n "Fetching latest Kora release metadata... "
    # gets the tarball url from the latest release via github api
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
    # removes existing installation to avoid conflict errors
    kpackagetool6 -t Plasma/Applet -r plasmusic-toolbar >/dev/null 2>&1 || true
    if kpackagetool6 -t Plasma/Applet -i "$TMP_DIR/plasmusic-toolbar/src" >"$TMP_DIR/plasmusic_pkg.log" 2>&1; then
        echo "OK"
    else
        echo "FAILED"
        echo "--- error log ---"
        cat -v "$TMP_DIR/plasmusic_pkg.log"
        exit 1
    fi
