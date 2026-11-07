# Agate OpenPGP, GnuPG, smartcard, and Git signing utilities.
# Optional config: ${XDG_CONFIG_HOME:-~/.config}/agate/pgp.conf
# Environment overrides: AGATE_PGP_KEY, AGATE_PGP_SERVERS.
# Never store private keys or passwords in the configuration.
[group("development")]
agate-pgp $action="" $target="" $key="" $option="":
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
    read -r -a SERVERS <<< "${AGATE_PGP_SERVERS:-${config_servers:-hkps://keys.openpgp.org hkps://keyserver.ubuntu.com hkps://keys.mailvelope.com hkps://pgp.mit.edu}}"

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
    Usage: ujust agate-pgp <action> [target] [key] [option]

    Keys and security:
      status                        Show GPG agent and Git signing state
      list [all|public|secret]      List local public and secret keys
      card                          Inspect OpenPGP smartcard / YubiKey
      reload [pcscd]                Restart GPG stack; optionally restart PC/SC
      doctor                        Diagnose GPG, smartcard, SSH agent and Git
      audit                         Check key expiry, algorithms and capabilities
      fingerprint [key|select]      Copy or print full fingerprint (optional QR)
      import [file|ID|email]        Import a public key (file, WKD or server)
      lookup <email|fingerprint>    Inspect remote keys, confirm before import
      search <query>                Search keyservers without importing
      refresh [key|select]         Refresh a known key
      publish [key|select]         Publish a public key (confirmation)
      publish-check [key|select]   Compare local and remote certificate copies
      export [key|select] [file]   Export armored public key
      edit [key|select]            Edit GPG key
      trust [key|select]           Edit local ownertrust interactively
      delete [key|select]          Delete local key (fingerprint confirmation)
      revoke [key|select] [file]   Generate revocation certificate (NOT automatic)
      rotate [key|select]          Guide key/subkey expiration or rotation

    Cryptography and Git:
      encrypt [file] [key] [--self] Encrypt files, stdin or Wayland clipboard
      decrypt [file]               Decrypt to stdout
      sign [file] [key] [--detach]  Clear-sign or create detached signature
      verify [sig] [file]          Verify a signature
      git-sign [gpg|ssh|off|status] [key|select] [global|local]
                                    Configure Git signing; SSH uses SSH_AUTH_SOCK

    Backups:
      backup [base-dir] [public|secret]     Save keys/ownertrust; encrypted secret option
      restore <backup-dir> [public|all]    Verify and restore a backup

    Config: ${XDG_CONFIG_HOME:-~/.config}/agate/pgp.conf
      default_key=FULL_FINGERPRINT
      keyservers=hkps://keys.openpgp.org hkps://keyserver.ubuntu.com

    Environment overrides: AGATE_PGP_KEY, AGATE_PGP_SERVERS.
    'select' opens a key picker. Clipboard is used when no file or piped input.
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

    tempdir() {
        local root="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
        mkdir -p -- "$root"
        mktemp -d "$root/agate-pgp.XXXXXXXX"
    }

    key_exists() {
        [[ -n "$(fingerprint "$1" "${2:-public}" 2>/dev/null || true)" ]]
    }

    show_or_copy() {
        if [[ -t 1 ]] && command -v wl-copy >/dev/null 2>&1; then
            printf '%s\n' "$1" | wl-copy --type text/plain
            info 'Copied to Wayland clipboard.'
        else
            printf '%s\n' "$1"
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
        doctor)
            need gpg
            need gpgconf
            info '=== OpenPGP diagnostics ==='
            gpg --version | head -n 1
            printf 'GPG home: %s\n' "$(gpgconf --list-dirs homedir)"
            printf 'Agent socket: %s\n' "$(gpgconf --list-dirs agent-socket)"
            if command -v gpg-connect-agent >/dev/null 2>&1 &&
               gpg-connect-agent /bye >/dev/null 2>&1; then
                info 'GPG agent: reachable'
            else
                info 'GPG agent: unavailable'
            fi
            if command -v timeout >/dev/null 2>&1; then
                timeout 6 gpg --card-status >/dev/null 2>&1 && info 'OpenPGP card: detected' || info 'OpenPGP card: not detected or unavailable'
            else
                info 'OpenPGP card: check with ujust pgp card'
            fi
            if command -v systemctl >/dev/null 2>&1; then
                printf 'PC/SC: %s\n' "$(systemctl is-active pcscd.socket 2>/dev/null || echo unavailable)"
            fi
            if command -v pinentry-qt >/dev/null 2>&1; then
                info 'Pinentry: pinentry-qt installed'
            elif command -v pinentry >/dev/null 2>&1; then
                info 'Pinentry: installed'
            else
                info 'Pinentry: not found in PATH (agent may configure a custom path)'
            fi
            if [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
                printf 'SSH agent socket: %s\n' "$SSH_AUTH_SOCK"
                if command -v ssh-add >/dev/null 2>&1; then
                    ssh-add -l || true
                fi
            else
                info 'SSH agent: no active socket (check Bitwarden desktop if used)'
            fi
            if command -v git >/dev/null 2>&1; then
                printf 'Git signing: %s (%s)\n' "$(git config --get commit.gpgsign || echo unset)" "$(git config --get gpg.format || echo openpgp)"
                printf 'Git signing key: %s\n' "$(git config --get user.signingkey || echo unset)"
            fi
            info 'Use ujust pgp audit for key lifecycle checks.'
            ;;
        audit)
            need gpg
            info '=== Local public-key audit ==='
            gpg --batch --with-colons --list-keys |
                awk -F: -v now="$(date +%s)" '
                function warn(msg) { printf "  WARNING: %s\n", msg; issues++ }
                function expiry(x, kind) {
                    if (x == "" || x == 0) return
                    if (x < now) warn(kind " expired")
                    else if (x < now + 90*86400) warn(kind " expires in " int((x-now)/86400) " days")
                }
                function finish() {
                    if (!active) return
                    if (!has_encryption) warn("no encryption-capable subkey found (may be intentional)")
                }
                $1 == "pub" {
                    finish(); active=1; has_encryption=0
                    printf "Key: %s (algorithm %s, %s bits)\n", $5, $4, $3
                    if ($2 == "r") warn("revoked")
                    if ($2 == "d") warn("disabled")
                    if ($4 == 1 && $3+0 < 3072) warn("RSA key shorter than 3072 bits")
                    expiry($7,"primary key")
                    if (tolower($12) ~ /e/) has_encryption=1
                }
                $1 == "sub" {
                    if (tolower($12) ~ /e/) has_encryption=1
                    if ($4 == 1 && $3+0 < 3072) warn("RSA subkey shorter than 3072 bits")
                    expiry($7,"subkey " $5)
                }
                END {finish(); print "Audit finished. Review warnings against your intended usage."}
            '
            info 'Secret-key stubs on hardware tokens are not backups. Audit cannot prove trust or recovery readiness.'
            ;;
        fingerprint)
            need gpg
            active="$(selected_key "$target" public)"
            fpr="$(fingerprint "$active")"
            [[ -n "$fpr" ]] || die 'public key not found'
            if [[ "$key" == qr ]]; then
                need qrencode
                qrencode -t ANSIUTF8 "$fpr"
            else
                show_or_copy "$fpr"
            fi
            ;;
        lookup)
            need gpg
            [[ -n "$target" ]] || die 'usage: ujust pgp lookup <email|fingerprint>'
            tmp="$(tempdir)"
            trap 'rm -rf -- "$tmp"' EXIT
            chmod 700 "$tmp"
            mkdir -m 700 "$tmp/gnupg"
            found=false
            if [[ "$target" == *'@'* ]]; then
                for method in wkd dane keyserver; do
                    info "Looking up $target via $method..."
                    if [[ "$method" == keyserver ]]; then
                        for server in "${SERVERS[@]}"; do
                            if gpg --homedir "$tmp/gnupg" --batch --keyserver "$server" --keyserver-options timeout=10 \
                                --auto-key-locate clear,nodefault,keyserver --locate-external-keys "$target" >/dev/null 2>&1; then
                                found=true; break
                            fi
                        done
                    elif gpg --homedir "$tmp/gnupg" --batch --auto-key-locate "clear,nodefault,$method" \
                        --locate-external-keys "$target" >/dev/null 2>&1; then
                        found=true
                    fi
                    [[ "$found" == true ]] && break
                done
            elif [[ "${target#0x}" =~ ^[[:xdigit:]]{16,64}$ ]]; then
                for server in "${SERVERS[@]}"; do
                    info "Looking up ${target#0x} at $server..."
                    if gpg --homedir "$tmp/gnupg" --batch --keyserver "$server" --keyserver-options timeout=10 \
                        --recv-keys "${target#0x}" >/dev/null 2>&1; then
                        found=true; break
                    fi
                done
            else
                die 'provide an email address or a fingerprint/key ID of at least 16 hex characters'
            fi
            [[ "$found" == true ]] || die 'no remote key discovered'
            info 'Discovered key (remote source does NOT prove identity):'
            gpg --homedir "$tmp/gnupg" --list-keys --fingerprint --keyid-format LONG
            confirm 'Import the displayed key(s) into your local keyring?'
            gpg --homedir "$tmp/gnupg" --export | gpg --import
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
        publish-check)
            need gpg
            active="$(selected_key "$target" public)"
            fpr="$(fingerprint "$active")"
            [[ -n "$fpr" ]] || die 'public key not found'
            tmp="$(tempdir)"; trap 'rm -rf -- "$tmp"' EXIT
            mkdir -m 700 "$tmp/gnupg"
            local_hash="$(gpg --batch --export-options export-minimal --export "$fpr" | sha256sum | awk '{print $1}')"
            for server in "${SERVERS[@]}"; do
                info "Checking $server..."
                if gpg --homedir "$tmp/gnupg" --batch --keyserver "$server" --keyserver-options timeout=10 \
                    --recv-keys "$fpr" >/dev/null 2>&1; then
                    remote_hash="$(gpg --homedir "$tmp/gnupg" --batch --export-options export-minimal --export "$fpr" | sha256sum | awk '{print $1}')"
                    if [[ "$remote_hash" == "$local_hash" ]]; then
                        printf '  %s: same minimal export\n' "$server"
                    else
                        printf '  %s: certificate differs (may strip UIDs/signatures)\n' "$server"
                    fi
                else
                    printf '  %s: unavailable or not published\n' "$server"
                fi
                gpg --homedir "$tmp/gnupg" --batch --yes --delete-keys "$fpr" >/dev/null 2>&1 || true
            done
            ;;
        rotate)
            need gpg
            active="$(selected_key "${target:-select}" secret)"
            fpr="$(fingerprint "$active" secret)"
            [[ -n "$fpr" ]] || die 'local secret key or card stub required'
            info "Key: $fpr"
            info 'Review subkeys, enter "key N" to select a subkey, "expire" to renew, "addkey" to create a new subkey, "save" to commit.'
            info 'This interactive operation does not automatically publish or revoke older subkeys.'
            confirm 'Launch the GnuPG key editor for rotation?'
            gpg --edit-key "$fpr" < /dev/tty
            ;;
        trust)
            need gpg
            active="$(selected_key "${target:-select}" public)"
            fpr="$(fingerprint "$active")"
            [[ -n "$fpr" ]] || die 'key not found'
            info 'Ownertrust determines how much this key may certify other identities; it does not itself verify identity.'
            info 'Use the "trust" command in the editor, then "save".'
            gpg --edit-key "$fpr" < /dev/tty
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
                local_self=false
                if [[ "$option" == --self || "$key" == --self ]]; then
                    local_self=true
                    [[ "$key" == --self ]] && active="$DEFAULT_KEY"
                elif [[ -n "$option" ]]; then
                    die 'encrypt supports optional --self as the final argument'
                fi
                options=(--armor --trust-model auto --recipient "$active")
                if [[ "$local_self" == true && "$active" != "$DEFAULT_KEY" ]]; then
                    options+=(--recipient "$DEFAULT_KEY")
                fi
                options+=(--encrypt)
            else
                if [[ "$option" == --detach ]]; then
                    options=(--armor --local-user "$active" --detach-sign)
                elif [[ -z "$option" ]]; then
                    options=(--armor --local-user "$active" --clearsign)
                else
                    die 'sign supports optional --detach as the final argument'
                fi
            fi
            if [[ -n "$input" ]]; then
                [[ -f "$input" ]] || die "file not found: $input"
                output="${input}.asc"
                if [[ "$action" == sign && "$option" == --detach ]]; then
                    output="${input}.sig.asc"
                fi
                [[ ! -e "$output" ]] || die "output already exists: $output"
                gpg --output "$output" "${options[@]}" -- "$input"
                info "Created: $output"
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
        backup)
            need gpg
            need sha256sum
            base="${target:-${XDG_STATE_HOME:-$HOME/.local/state}/agate/pgp/backups}"
            mode="${key:-public}"
            [[ "$mode" == public || "$mode" == secret ]] || die 'backup mode must be public or secret'
            mkdir -p -m 700 -- "$base"
            bundle="$(mktemp -d "$base/backup-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXXXX")"
            info "Writing backup to: $bundle"
            gpg --export > "$bundle/public-keys.gpg"
            gpg --export-ownertrust > "$bundle/ownertrust.txt"
            if [[ -f "$config" ]]; then cp -- "$config" "$bundle/pgp.conf"; fi
            if [[ "$mode" == secret ]]; then
                info 'Secret-key backup requested. The encrypted export will require a separate passphrase.'
                info 'Hardware-only keys/card stubs CANNOT be restored from a secret-key export.'
                confirm 'Continue with an encrypted secret-key backup?'
                gpg --export-secret-keys | gpg --symmetric --cipher-algo AES256 \
                    --output "$bundle/secret-keys.gpg"
                [[ -s "$bundle/secret-keys.gpg" ]] || die 'encrypted secret-key export is empty'
            fi
            (cd "$bundle" && sha256sum public-keys.gpg ownertrust.txt \
                $( [[ -f pgp.conf ]] && printf 'pgp.conf ' ) \
                $( [[ -f secret-keys.gpg ]] && printf 'secret-keys.gpg' ) > SHA256SUMS)
            info 'Backup complete. Keep encrypted backups off-device and test restoration.'
            ;;
        restore)
            need gpg
            need sha256sum
            [[ -n "$target" && -d "$target" ]] || die 'usage: ujust pgp restore <backup-dir> [public|all]'
            mode="${key:-public}"
            [[ "$mode" == public || "$mode" == all ]] || die 'restore mode must be public or all'
            (cd "$target" && sha256sum -c SHA256SUMS) || die 'backup checksum validation failed'
            info "Restoring local public keys from $target..."
            gpg --import "$target/public-keys.gpg"
            if [[ -s "$target/ownertrust.txt" ]]; then
                info 'Importing ownertrust can change which keys your machine considers trusted.'
                if [[ -t 0 ]]; then
                    tty_read 'Import ownertrust? Type TRUST to confirm: '
                    if [[ "$REPLY" == TRUST ]]; then gpg --import-ownertrust "$target/ownertrust.txt"; fi
                else
                    info 'Skipping ownertrust import (non-interactive session).'
                fi
            fi
            if [[ "$mode" == all && -f "$target/secret-keys.gpg" ]]; then
                confirm 'Decrypt and import encrypted private keys into this machine?'
                gpg --decrypt "$target/secret-keys.gpg" | gpg --import
            fi
            info 'Restore finished. Validate your expected keys, card stubs and trust database.'
            ;;
        git-sign)
            need git
            mode="${target:-status}"
            scope="${option:-global}"
            [[ "$scope" == global || "$scope" == local ]] || die 'scope must be global or local'
            if [[ "$scope" == local ]]; then
                git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die 'local Git scope requires a Git repository'
            fi
            case "$mode" in
                status)
                    printf 'Signing enabled: %s\n' "$(git config --get commit.gpgsign || echo unset)"
                    printf 'Signing format: %s\n' "$(git config --get gpg.format || echo openpgp)"
                    printf 'Signing key: %s\n' "$(git config --get user.signingkey || echo unset)"
                    ;;
                off)
                    git config --"$scope" commit.gpgsign false
                    info "Git commit signing disabled ($scope scope)."
                    ;;
                gpg|yubikey)
                    need gpg
                    active="$(selected_key "$key" secret)"
                    fpr="$(fingerprint "$active" secret)"
                    [[ -n "$fpr" ]] || die 'GPG signing key or card stub not available'
                    git config --"$scope" gpg.format openpgp
                    git config --"$scope" user.signingkey "$fpr"
                    git config --"$scope" commit.gpgsign true
                    info "Git OpenPGP signing enabled: $fpr ($scope scope)"
                    ;;
                ssh)
                    need ssh-add
                    [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]] || die 'SSH_AUTH_SOCK does not point to an active SSH agent'
                    if [[ "$key" == select ]]; then
                        mapfile -t ssh_keys < <(ssh-add -L | grep -E '^ssh-|^sk-' || true)
                        ((${#ssh_keys[@]} > 0)) || die 'no SSH public keys available from the agent'
                        for i in "${!ssh_keys[@]}"; do
                            printf '  %d) %s\n' "$((i+1))" "${ssh_keys[$i]}" >&2
                        done
                        tty_read 'Select SSH key number: '
                        [[ "$REPLY" =~ ^[0-9]+$ ]] && ((10#$REPLY >= 1)) && ((10#$REPLY <= ${#ssh_keys[@]})) || die 'invalid selection'
                        active="${ssh_keys[$((10#$REPLY-1))]}"
                    elif [[ -f "$key" ]]; then
                        IFS= read -r active < "$key"
                    else
                        active="$key"
                    fi
                    [[ "$active" == ssh-* || "$active" == sk-* ]] || die 'SSH signing requires an agent public key, public key file, or select'
                    active_type="${active%% *}"
                    active_data="${active#* }"; active_data="${active_data%% *}"
                    [[ -n "$active_data" ]] || die 'invalid SSH public key format'
                    if ! ssh-add -L | awk '{print $1" "$2}' | grep -Fxq "$active_type $active_data"; then
                        die 'selected SSH signing key is not currently available in SSH_AUTH_SOCK'
                    fi
                    git config --"$scope" gpg.format ssh
                    git config --"$scope" user.signingkey "$active"
                    git config --"$scope" commit.gpgsign true
                    info "Git SSH signing enabled ($scope scope). Bitwarden SSH Agent may ask for authorization."
                    info 'For local signature verification, configure gpg.ssh.allowedSignersFile separately.'
                    ;;
                *) die 'git-sign accepts status, gpg, ssh, or off' ;;
            esac
            ;;
        *) die "unknown action '$action'; run 'ujust pgp' for help" ;;
    esac
