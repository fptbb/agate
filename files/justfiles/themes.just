# Manage Spicetify and Spotify Flatpak without resetting customizations
[group("utilities")]
agate-spicetify action="":
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077

    action="{{action}}"
    spotify_id="com.spotify.Client"
    marketplace_url="https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh"
    config_dir="${SPICETIFY_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/spicetify}"
    spotify_path=""
    installer=""
    trap '[[ -z "$installer" ]] || rm -f -- "$installer"' EXIT

    die() { printf 'error: %s\n' "$*" >&2; exit 1; }
    need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }
    confirm() {
        local answer
        read -r -p "$1 [y/N] " answer </dev/tty || die 'An interactive terminal is required'
        [[ "$answer" =~ ^[Yy]$ ]]
    }

    if [[ -z "$action" || "$action" == help || "$action" == --help ]]; then
        printf '%s\n' \
            'Usage: ujust agate-spicetify <action>' \
            'Actions:' \
            '  all          Full workflow: dependencies, permissions, config, update, repair, Marketplace' \
            '  setup        Alias of all' \
            '  status       Show installed components' \
            '  permissions  Repair Flatpak write permissions' \
            '  apply        Reapply configured themes and extensions' \
            '  repair       Restore, back up and reapply Spotify modifications' \
            '  update       Update Spicetify, then restore/back up/apply' \
            '  marketplace  Install/update Marketplace' \
            '  restore      Return Spotify to vanilla (keep customization files)'
        exit 0
    fi
    case "$action" in
        all|setup|status|permissions|apply|repair|update|marketplace|restore) ;;
        *) die "Unknown action: $action" ;;
    esac

    if [[ "$action" == status ]]; then
        if command -v spicetify >/dev/null; then
            spicetify --version
        else
            echo 'Spicetify: not installed'
        fi
        if command -v flatpak >/dev/null && flatpak info "$spotify_id" >/dev/null 2>&1; then
            echo "Spotify: $(flatpak info --show-location "$spotify_id")"
        else
            echo 'Spotify Flatpak: not installed'
        fi
        [[ ! -d "$config_dir/CustomApps/marketplace" ]] || echo 'Marketplace: installed'
        exit 0
    fi

    if [[ "$action" != permissions ]] && ! command -v spicetify >/dev/null 2>&1; then
        need brew
        confirm 'Install spicetify-cli via Homebrew?' || die 'Cancelled'
        brew install spicetify-cli
    fi
    need flatpak
    if ! flatpak info "$spotify_id" >/dev/null 2>&1; then
        confirm 'Install Spotify via Flathub?' || die 'Cancelled'
        flatpak install -y flathub "$spotify_id"
    fi

    spotify_path="$(flatpak info --show-location "$spotify_id")/files/extra/share/spotify"
    [[ -d "$spotify_path/Apps" ]] || die "Spotify Apps directory not found: $spotify_path/Apps"

    backup_state() {
        local root snapshot spotify_settings
        root="${XDG_STATE_HOME:-$HOME/.local/state}/agate/spicetify-backups"
        mkdir -p -- "$root"
        snapshot="$(mktemp -d "$root/$(date +%Y%m%d-%H%M%S)-XXXXXXXX")"
        [[ ! -d "$config_dir" ]] || cp -a -- "$config_dir" "$snapshot/spicetify"
        spotify_settings="$HOME/.var/app/$spotify_id/config/spotify"
        [[ ! -d "$spotify_settings" ]] || cp -a -- "$spotify_settings" "$snapshot/spotify-config"
        printf 'Customization backup: %s\n' "$snapshot"
    }

    fix_permissions() {
        if [[ -O "$spotify_path" ]]; then
            chmod u+rw "$spotify_path"
            chmod -R u+rwX "$spotify_path/Apps"
        else
            need sudo
            need setfacl
            sudo -v
            sudo setfacl -m "u:$(id -u):rwx" "$spotify_path"
            sudo setfacl -R -m "u:$(id -u):rwX" "$spotify_path/Apps"
        fi
    }

    # Permissions always come before the configuration and update commands.
    if [[ "$action" != permissions ]]; then backup_state; fi
    fix_permissions
    if [[ "$action" == permissions ]]; then
        echo 'Spotify permissions repaired.'
        exit 0
    fi

    need spicetify
    prefs_path="$HOME/.var/app/$spotify_id/config/spotify/prefs"
    if [[ ! -f "$prefs_path" && -f "$HOME/.config/spotify/prefs" ]]; then
        prefs_path="$HOME/.config/spotify/prefs"
    fi
    spicetify config spotify_path "$spotify_path"
    spicetify config prefs_path "$prefs_path"
    [[ -f "$prefs_path" ]] || echo 'Warning: Spotify prefs missing; open and log into Spotify first.' >&2

    install_marketplace() {
        need curl
        installer="$(mktemp "${TMPDIR:-/tmp}/agate-marketplace.XXXXXXXX")"
        curl -fsSL --retry 2 --connect-timeout 10 "$marketplace_url" -o "$installer"
        sh "$installer"
    }

    case "$action" in
        all|setup)
            spicetify update
            spicetify restore backup apply
            install_marketplace
            ;;
        update)
            spicetify update
            spicetify restore backup apply
            ;;
        repair) spicetify restore backup apply ;;
        apply) spicetify backup apply ;;
        restore) spicetify restore ;;
        marketplace) install_marketplace ;;
    esac
    echo 'Done.'
