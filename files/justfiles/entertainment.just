# justfile

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

    spicetify restore backup apply