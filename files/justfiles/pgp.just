# Agate OpenPGP, GnuPG, smartcard, and Git signing utilities.
# Optional config: ${XDG_CONFIG_HOME:-~/.config}/agate/pgp.conf
# Environment overrides: AGATE_PGP_KEY and AGATE_PGP_SERVERS.
# Never store private keys or passwords in the configuration.
[group("development")]
pgp $action="" $target="" $key="":
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077

    # Simple non-executable, XDG-compliant settings (environment wins).
    config="${XDG_CONFIG_HOME:-$HOME/.config}/agate/pgp.conf"
    config_key=""
    config_servers=""
    if [[ -f "$config" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
            case "$line" in
                default_key=*) config_key="${line#*=}" ;;
                keyservers=*) config_servers="${line#*=}" ;;
                *) printf 'warning: unknown setting in %s: %s\n' "$config" "$line" >&2 ;;
            esac
        done < "$config"
    fi
    DEFAULT_KEY="${AGATE_PGP_KEY:-${config_key:-9F8D0697AD085F839D56C5DCD334181D1ABE834D}}"
    read -r -a SERVERS <<< "${AGATE_PGP_SERVERS:-${config_servers:-hkps://keyserver.ubuntu.com hkps://keys.openpgp.org}}"

    die() { printf 'error: %s\n' "$*" >&2; exit 1; }
    info() { printf '%s\n' "$*" >&2; }
    need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
    tty_read() {
        [[ -r /dev/tty ]] || die 'an interactive terminal is required'
        printf '%s' "$1" >&2
        IFS= read -r REPLY < /dev/tty || die 'could not read from terminal'
    }
    confirm() { tty_read "$1 (type YES): "; [[ "$REPLY" == YES ]] || die 'cancelled'; }

    help() {
        cat <<'HELP'
    Usage: ujust pgp <action> [target] [key]

    Keys and smartcards:
      status                       Show default key, agent, and Git signing status
      list [all|public|secret]     List keys in the local GPG keyring
      card                         Show YubiKey/OpenPGP smartcard status
      reload [pcscd]               Reload GPG agent; optionally restart PC/SC
      import [file|ID|email]       Import from file, keyserver, WKD, stdin, or clipboard
      search <email|query>         Search public keyservers without local import
      refresh [key]                Refresh an existing key from a keyserver
      export [key|select] [file]   Export public key to clipboard, stdout, or file
      publish [key|select]         Publish a key to configured keyservers
      edit [key|select]            Open the interactive GPG key editor
      delete [key|select]          Delete a local public/secret key (with confirmation)
      revoke [key|select] [file]   Create revocation certificate (optional local import)

    Crypto and Git:
      encrypt [file|select] [key]  Encrypt file, piped input, or clipboard
      decrypt [file]               Decrypt file, piped input, or clipboard to stdout
      sign [file|select] [key]     Clear-sign file, piped input, or clipboard
      verify [signature] [file]    Verify signed content or detached signature
      git-sign [yubikey|select|off|status|key]
                                   Choose the global Git signing identity

    Defaults: ~/.config/agate/pgp.conf (default_key=..., keyservers=...)
    Environment overrides: AGATE_PGP_KEY and AGATE_PGP_SERVERS.
    Use 'select' for interactive key selection; stdin/stdout in pipelines.
    HELP
    }

    # Select a full fingerprint, rather than an ambiguous short key ID.
    choose_key() {
        local kind="$1" listing index i uid
        local -a keys=()
        if [[ "$kind" == secret ]]; then
            listing="$(gpg --batch --with-colons --list-secret-keys)" || return 1
            mapfile -t keys < <(awk -F: '
                $1 == "sec" { want=1; next }
                want && $1 == "fpr" { print $10; want=0 }
            ' <<< "$listing")
        else
            listing="$(gpg --batch --with-colons --list-keys)" || return 1
            mapfile -t keys < <(awk -F: '
                $1 == "pub" { want=1; next }
                want && $1 == "fpr" { print $10; want=0 }
            ' <<< "$listing")
        fi
        ((${#keys[@]} > 0)) || die "no $kind keys found"
        info "Available $kind keys:"
        for i in "${!keys[@]}"; do
            uid="$(gpg --batch --with-colons --list-keys "${keys[$i]}" 2>/dev/null |
                awk -F: '$1=="uid" {print $10; exit}')"
            printf '  %d) %s %s\n' "$((i+1))" "${keys[$i]}" "$uid" >&2
        done
        tty_read 'Select key number (Enter to cancel): '
        index="$REPLY"
        [[ "$index" =~ ^[0-9]+$ ]] && ((10#$index >= 1)) && ((10#$index <= ${#keys[@]})) || die 'selection cancelled or invalid'
        printf '%s\n' "${keys[$((10#$index-1))]}"
    }

    selected_key() {
        local candidate="${1:-}" kind="${2:-public}"
        if [[ "$candidate" == select ]]; then
            choose_key "$kind"
        else
            printf '%s\n' "${candidate:-$DEFAULT_KEY}"
        fi
    }

    fingerprint() {
        local candidate="$1" kind="${2:-public}" output
        if [[ "$kind" == secret ]]; then
            output="$(gpg --batch --with-colons --list-secret-keys "$candidate")" || return 1
        else
            output="$(gpg --batch --with-colons --list-keys "$candidate")" || return 1
        fi
        awk -F: '
            $1 == "sec" || $1 == "pub" { want=1; next }
            want && $1 == "fpr" { print $10; exit }
        ' <<< "$output"
    }

    # Preserve binary streams and trailing newlines: never store plaintext in Bash variables.
    input_stream() {
        if [[ -t 0 ]]; then
            need wl-paste
            wl-paste
        else
            cat
        fi
    }
    crypto_stream() {
        local -a args=("$@")
        if [[ -t 1 ]]; then
            need wl-copy
            input_stream | gpg "${args[@]}" | wl-copy --type text/plain
            info 'Output copied to Wayland clipboard.'
        else
            input_stream | gpg "${args[@]}"
        fi
    }

    case "$action" in
        ''|help|-h|--help)
            help
            exit 0
            ;;
        status)
            need gpg
            info "Default key: $DEFAULT_KEY"
            printf 'GPG: %s\n' "$(gpg --version | head -n 1)"
            printf 'GPG agent socket: %s\n' "$(gpgconf --list-dirs agent-socket)"
            printf 'SSH_AUTH_SOCK: %s\n' "${SSH_AUTH_SOCK:-unset}"
            printf 'Git sign: %s\n' "$(git config --global --get commit.gpgsign 2>/dev/null || echo unset)"
            printf 'Git format: %s\n' "$(git config --global --get gpg.format 2>/dev/null || echo openpgp)"
            printf 'Git key: %s\n' "$(git config --global --get user.signingkey 2>/dev/null || echo unset)"
            ;;
        list)
            need gpg
            case "${target:-all}" in
                all)    gpg --list-keys --keyid-format LONG; printf '\n'; gpg --list-secret-keys --keyid-format LONG ;;
                public) gpg --list-keys --keyid-format LONG ;;
                secret) gpg --list-secret-keys --keyid-format LONG ;;
                *) die 'list accepts all, public, or secret' ;;
            esac
            ;;
        card)
            need gpg
            gpg --card-status
            ;;
        reload)
            need gpgconf
            need gpg-connect-agent
            gpgconf --kill scdaemon || true
            gpgconf --kill gpg-agent || true
            gpgconf --kill dirmngr || true
            gpg-connect-agent updatestartuptty /bye >/dev/null
            if [[ "$target" == pcscd ]]; then
                need sudo
                sudo systemctl restart pcscd.socket pcscd.service
            elif [[ -n "$target" ]]; then
                die 'reload accepts only optional pcscd'
            fi
            info 'GPG/smartcard stack reloaded. Existing SSH_AUTH_SOCK was not changed.'
            if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
                ssh-add -L 2>/dev/null || true
            fi
            ;;
        import)
            need gpg
            if [[ -z "$target" ]]; then
                input_stream | gpg --import
            elif [[ -f "$target" ]]; then
                gpg --show-keys -- "$target"
                gpg --import -- "$target"
            elif [[ "$target" == *'@'* ]]; then
                gpg --auto-key-locate wkd,keyserver --locate-keys "$target"
            elif [[ "${target#0x}" =~ ^[[:xdigit:]]{8,40}$ ]]; then
                for server in "${SERVERS[@]}"; do
                    info "Querying $server..."
                    if gpg --keyserver "$server" --keyserver-options timeout=10 --recv-keys "${target#0x}"; then
                        exit 0
                    fi
                done
                die 'key not found on configured servers'
            else
                die 'expected an existing file, email, or hexadecimal key ID/fingerprint'
            fi
            ;;
        search)
            need gpg
            [[ -n "$target" ]] || die 'usage: ujust pgp search <email|query>'
            found=false
            for server in "${SERVERS[@]}"; do
                info "Searching $server..."
                # No selected key is imported in batch/no-TTY mode.
                if gpg --batch --no-tty --keyserver-options timeout=10 --keyserver "$server" \
                    --search-keys "$target" < /dev/null; then
                    found=true
                fi
            done
            [[ "$found" == true ]] || die 'no search results found'
            ;;
        refresh)
            need gpg
            active="$(selected_key "$target" public)"
            gpg --refresh-keys "$active"
            ;;
        export)
            need gpg
            active="$(selected_key "$target" public)"
            [[ -n "$(fingerprint "$active")" ]] || die 'public key not found'
            if [[ -n "$key" ]]; then
                [[ ! -e "$key" ]] || die "output already exists: $key"
                gpg --armor --output "$key" --export "$active"
                info "Public key exported: $key"
            elif [[ -t 1 ]]; then
                need wl-copy
                gpg --armor --export "$active" | wl-copy --type text/plain
                info 'Public key copied to Wayland clipboard.'
            else
                gpg --armor --export "$active"
            fi
            ;;
        publish)
            need gpg
            active="$(selected_key "$target" public)"
            fpr="$(fingerprint "$active")"
            [[ -n "$fpr" ]] || die 'public key not found'
            info "Publishing fingerprint: $fpr"
            info 'Keyserver publication can be effectively permanent.'
            confirm 'Publish this key to the configured servers?'
            successes=0
            for server in "${SERVERS[@]}"; do
                info "Sending to $server..."
                if gpg --keyserver "$server" --keyserver-options timeout=10 --send-keys "$fpr"; then
                    ((successes+=1))
                else
                    info "warning: upload failed to $server"
                fi
            done
            ((successes>0)) || die 'no keyserver accepted the key'
            info 'Publication finished. keys.openpgp.org requires email verification.'
            ;;
        edit)
            need gpg
            active="$(selected_key "${target:-select}" public)"
            gpg --edit-key "$active" < /dev/tty
            ;;
        delete)
            need gpg
            active="$(selected_key "${target:-select}" public)"
            fpr="$(fingerprint "$active")"
            [[ -n "$fpr" ]] || die 'public key not found'
            info "Selected fingerprint: $fpr"
            info 'This removes local key material only; a keyserver publication is unaffected.'
            tty_read 'Type the FULL fingerprint to delete this key: '
            [[ "${REPLY^^}" == "${fpr^^}" ]] || die 'cancelled: fingerprint did not match'
            if [[ -n "$(fingerprint "$fpr" secret 2>/dev/null || true)" ]]; then
                gpg --batch --yes --delete-secret-and-public-key "$fpr"
            else
                gpg --batch --yes --delete-keys "$fpr"
            fi
            info 'Local key deleted.'
            ;;
        revoke)
            need gpg
            active="$(selected_key "${target:-select}" secret)"
            fpr="$(fingerprint "$active" secret)"
            [[ -n "$fpr" ]] || die 'secret key not available'
            rev_file="${key:-REVOCATION-${fpr}.asc}"
            [[ ! -e "$rev_file" ]] || die "output already exists: $rev_file"
            info "Generating a revocation certificate for $fpr..."
            gpg --output "$rev_file" --gen-revoke "$fpr" < /dev/tty
            [[ -s "$rev_file" ]] || die 'revocation certificate generation failed'
            chmod 600 "$rev_file"
            info "Certificate written: $rev_file (0600). Keep it private."
            tty_read 'Import this certificate locally now? Type REVOKE to confirm: '
            if [[ "$REPLY" == REVOKE ]]; then
                gpg --import "$rev_file"
                info 'Revocation imported locally. Publish the revoked key separately if desired.'
            else
                info 'Certificate saved; the local key was not revoked.'
            fi
            ;;
        encrypt|sign)
            need gpg
            if [[ "$target" == select && -z "$key" ]]; then
                active="$(selected_key select "$([[ "$action" == sign ]] && echo secret || echo public)")"
                input=""
            else
                active="$(selected_key "$key" "$([[ "$action" == sign ]] && echo secret || echo public)")"
                input="$target"
            fi
            if [[ "$action" == encrypt ]]; then
                options=(--armor --recipient "$active" --encrypt)
            else
                options=(--armor --local-user "$active" --clearsign)
            fi
            if [[ -n "$input" ]]; then
                [[ -f "$input" ]] || die "file not found: $input"
                [[ ! -e "${input}.asc" ]] || die "output already exists: ${input}.asc"
                gpg --output "${input}.asc" "${options[@]}" -- "$input"
                info "Created: ${input}.asc"
            else
                crypto_stream "${options[@]}"
            fi
            ;;
        decrypt)
            need gpg
            if [[ -n "$target" ]]; then
                [[ -f "$target" ]] || die "file not found: $target"
                gpg --decrypt -- "$target"
            else
                input_stream | gpg --decrypt
            fi
            ;;
        verify)
            need gpg
            if [[ -n "$target" ]]; then
                if [[ -n "$key" ]]; then
                    gpg --verify -- "$target" "$key"
                else
                    gpg --verify -- "$target"
                fi
            else
                input_stream | gpg --verify
            fi
            ;;
        git-sign)
            need git
            if [[ -z "$target" ]]; then
                cat >&2 <<'MENU'
    Git commit signing:
      1) YubiKey/default GPG key
      2) Choose a GPG signing key
      3) Disable commit signing
      4) Show current settings
    MENU
                tty_read 'Select [1-4]: '
                case "$REPLY" in
                    1) target=yubikey ;;
                    2) target=select ;;
                    3) target=off ;;
                    4) target=status ;;
                    *) die 'invalid selection' ;;
                esac
            fi
            case "$target" in
                off) git config --global commit.gpgsign false; info 'Commit signing disabled.' ;;
                status)
                    printf 'Signing enabled: %s\n' "$(git config --global --get commit.gpgsign || echo unset)"
                    printf 'Signing format: %s\n' "$(git config --global --get gpg.format || echo openpgp)"
                    printf 'Signing key: %s\n' "$(git config --global --get user.signingkey || echo unset)"
                    ;;
                *)
                    need gpg
                    if [[ "$target" == yubikey ]]; then
                        active="$DEFAULT_KEY"
                    else
                        active="$(selected_key "$target" secret)"
                    fi
                    [[ -n "$(fingerprint "$active" secret)" ]] || die 'signing secret key/stub unavailable'
                    git config --global gpg.format openpgp
                    git config --global user.signingkey "$active"
                    git config --global commit.gpgsign true
                    info "Git now signs commits using OpenPGP key: $active"
                    ;;
            esac
            ;;
        *) die "unknown action '$action'; run 'ujust pgp' for help" ;;
    esac
