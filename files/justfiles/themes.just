# Manage Spicetify and the Spotify Flatpak
[group("utilities")]
agate-spicetify $action="":
    #!/usr/bin/env bash
    set -euo pipefail

    SPOTIFY_ID="com.spotify.Client"
    MARKETPLACE_URL="https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh"
    SPOTIFY_PATH=""
    PREFS_PATH=""
    MARKETPLACE_TMP=""

    cleanup() {
        [[ -z "$MARKETPLACE_TMP" ]] || rm -rf -- "$MARKETPLACE_TMP"
    }
    trap cleanup EXIT

    die() { printf 'error: %s\n' "$*" >&2; exit 1; }
    need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
    confirm() {
        local answer
        read -r -p "$1 [y/N] " answer < /dev/tty
        [[ "$answer" =~ ^[Yy]$ ]]
    }

    # Display help without checking dependencies or touching Spotify
    if [[ -z "$action" || "$action" == help || "$action" == --help ]]; then
        printf '%s\n' \
            'Usage: ujust agate-spicetify <action>' \
            '' \
            'Available actions:' \
            '  status       - Show Spotify, Spicetify and Marketplace status' \
            '  setup        - Install missing dependencies, configure, apply and install Marketplace' \
            '  apply        - Fix permissions and apply Spicetify' \
            '  update       - Upgrade Spicetify, reapply and update Marketplace' \
            '  restore      - Restore the original Spotify files' \
            '  marketplace  - Install or update Spicetify Marketplace' \
            '  permissions  - Repair Spotify Flatpak write permissions'
        exit 0
    fi

    case "$action" in
        status|setup|apply|update|restore|marketplace|permissions) ;;
        *) die "unknown action '$action' (run ujust agate-spicetify for help)" ;;
    esac

    ensure_spicetify() {
        if command -v spicetify >/dev/null 2>&1; then return; fi
        [[ "$action" == setup ]] || die "Spicetify is missing; run 'ujust agate-spicetify setup'"
        need brew
        confirm 'Install spicetify-cli using Homebrew?' || die 'cancelled'
        brew install spicetify-cli
        need spicetify
    }

    locate_spotify() {
        need flatpak
        local location
        location="$(flatpak info --show-location "$SPOTIFY_ID" 2>/dev/null)" || return 1
        SPOTIFY_PATH="$location/files/extra/share/spotify"
        [[ -d "$SPOTIFY_PATH/Apps" ]] || die "Spotify Apps directory not found: $SPOTIFY_PATH/Apps"
    }

    ensure_spotify() {
        if locate_spotify; then return; fi
        [[ "$action" == setup ]] || die "Spotify Flatpak is missing; run 'ujust agate-spicetify setup'"
        confirm 'Install Spotify from Flathub?' || die 'cancelled'
        flatpak install -y flathub "$SPOTIFY_ID"
        locate_spotify || die 'Spotify installed, but its application directory was not found'
    }

    configure_paths() {
        local flatpak_prefs="$HOME/.var/app/$SPOTIFY_ID/config/spotify/prefs"
        local legacy_prefs="$HOME/.config/spotify/prefs"
        if [[ -f "$flatpak_prefs" ]]; then
            PREFS_PATH="$flatpak_prefs"
        elif [[ -f "$legacy_prefs" ]]; then
            PREFS_PATH="$legacy_prefs"
        else
            die 'Spotify preferences missing; launch Spotify, log in, close it, and retry'
        fi
        spicetify config spotify_path "$SPOTIFY_PATH" prefs_path "$PREFS_PATH"
    }

    fix_permissions() {
        if [[ "$SPOTIFY_PATH" == "$HOME/"* ]]; then
            # User installation: modify only the current user's files
            chmod u+rw "$SPOTIFY_PATH"
            chmod -R u+rw "$SPOTIFY_PATH/Apps"
        else
            # System installation: grant access only to the current user
            need sudo
            need setfacl
            sudo -v
            sudo setfacl -m "u:$(id -u):rwx" "$SPOTIFY_PATH"
            sudo setfacl -R -m "u:$(id -u):rwX" "$SPOTIFY_PATH/Apps"
        fi
    }

    install_marketplace() {
        need curl
        MARKETPLACE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/agate-spicetify.XXXXXXXX")"
        curl -fsSL --retry 2 --connect-timeout 10 "$MARKETPLACE_URL" -o "$MARKETPLACE_TMP/marketplace-install.sh"
        sh "$MARKETPLACE_TMP/marketplace-install.sh"
        cleanup
        MARKETPLACE_TMP=""
    }

    if [[ "$action" == status ]]; then
        if command -v spicetify >/dev/null 2>&1; then
            printf 'Spicetify: %s\n' "$(spicetify --version 2>&1)"
        else
            echo 'Spicetify: not installed'
        fi
        if command -v flatpak >/dev/null 2>&1 && locate_spotify; then
            printf 'Spotify Flatpak: %s\n' "$SPOTIFY_PATH"
        else
            echo 'Spotify Flatpak: not installed'
        fi
        marketplace_dir="${SPICETIFY_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/spicetify}/CustomApps/marketplace"
        [[ -d "$marketplace_dir" ]] && echo 'Marketplace: installed' || echo 'Marketplace: not installed'
        exit 0
    fi

    if [[ "$action" == permissions ]]; then
        ensure_spotify
        fix_permissions
        echo 'Spotify Flatpak permissions updated.'
        exit 0
    fi

    ensure_spicetify
    ensure_spotify
    fix_permissions
    configure_paths

    case "$action" in
        setup)
            spicetify backup apply
            install_marketplace
            ;;
        apply)
            spicetify backup apply
            ;;
        update)
            if command -v brew >/dev/null 2>&1 && brew list --versions spicetify-cli >/dev/null 2>&1; then
                brew upgrade spicetify-cli
            else
                spicetify upgrade
            fi
            spicetify restore backup apply
            install_marketplace
            ;;
        restore)
            spicetify restore
            ;;
        marketplace)
            install_marketplace
            ;;
    esac

    echo 'Done.'
