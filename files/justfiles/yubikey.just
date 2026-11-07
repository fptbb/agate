# Manage YubiKey FIDO2 disk unlocking and KDE/PAM authentication

[group("system")]
agate-yubikey action="" target="":
    #!/usr/bin/env bash
    set -euo pipefail
    action="$1"
    target="$2"
     # PAM does not reliably inherit the shell's XDG_CONFIG_HOME during login.
     KEY_FILE="$HOME/.config/Yubico/u2f_keys"
     SDDM_PAM="/etc/pam.d/sddm"
     MARKER="# Agate YubiKey (managed)"
     help() {
         cat <<'EOF'
    Usage: ujust agate-yubikey <action> [device]
    LUKS:
      luks-enroll [device]  Enroll a FIDO2 key and configure crypttab
      luks-remove [device]  Remove FIDO2 slots and crypttab setting
    KDE / PAM:
      login                 Enable YubiKey for SDDM login only
      global                Enable YubiKey throughout system PAM
      disable               Disable Agate-managed U2F authentication
      register              Register primary YubiKey (replace mapping)
      add                   Register an additional YubiKey
      remove-keys           Remove local YubiKey mappings
    Other:
      status                Show configuration status
    If no LUKS device is specified, select one interactively.
    Keep a working LUKS password and an alternate login path.
    EOF
     }
     die() { printf 'error: %s\n' "$*" >&2; exit 1; }
     need() { for cmd in "$@"; do command -v "$cmd" >/dev/null || die "missing dependency: $cmd"; done; }
     root() { sudo -v; }
     select_luks() {
         local chosen="${1:-}" index
         if [[ -z "$chosen" ]]; then
             mapfile -t disks < <(sudo blkid -t TYPE=crypto_LUKS -o device)
             ((${#disks[@]})) || die "no LUKS devices found"
             if ((${#disks[@]} == 1)); then
                 chosen="${disks[0]}"
             else
                 printf 'LUKS devices:\n'
                 for index in "${!disks[@]}"; do printf '  %d) %s\n' "$((index + 1))" "${disks[index]}"; done
                 read -r -p 'Select device number: ' index
                 [[ "$index" =~ ^[0-9]+$ ]] && ((index >= 1 && index <= ${#disks[@]})) || die "invalid selection"
                 chosen="${disks[index - 1]}"
             fi
         fi
         [[ -b "$chosen" ]] || die "not a block device: $chosen"
         sudo cryptsetup isLuks "$chosen" || die "not a LUKS device: $chosen"
         [[ "$(sudo cryptsetup luksDump "$chosen" | awk '/^Version:/ {print $2; exit}')" == 2 ]] || die "FIDO2 enrollment requires LUKS2"
         DEVICE="$(readlink -f -- "$chosen")"
         UUID="$(sudo blkid -s UUID -o value "$DEVICE")"
         [[ -n "$UUID" ]] || die "cannot resolve device UUID"
     }
     # Edit only the selected device's entry; leave other volumes untouched.
     update_crypttab() {
         local mode="$1" tmp
         [[ -f /etc/crypttab ]] || die "/etc/crypttab is missing"
         tmp="$(mktemp)"
         if ! awk -v uuid="$UUID" -v device="$DEVICE" -v mode="$mode" '
             /^[[:space:]]*(#|$)/ {print; next}
             {
                 source=$2
                 if (source == "UUID=" uuid || source == "/dev/disk/by-uuid/" uuid || source == device) {
                     found++
                     original=(NF >= 4 ? $4 : "")
                     count=split(original, parts, ",")
                     opts=""
                     for (i=1; i<=count; i++) {
                         if (parts[i] != "" && parts[i] != "-" && parts[i] != "none" && parts[i] != "fido2-device=auto")
                             opts=opts (opts == "" ? "" : ",") parts[i]
                     }
                     if (mode == "add") opts=opts (opts == "" ? "" : ",") "fido2-device=auto"
                     if (NF < 3) $3="none"
                     if (opts == "") NF=3
                     else $4=opts
                 }
                 print
             }
             END {if (found != 1) exit 2}
         ' /etc/crypttab > "$tmp"; then
             rm -f -- "$tmp"
             die "expected exactly one crypttab entry for UUID=$UUID; no changes made"
         fi
         sudo cp -a /etc/crypttab "/etc/crypttab.agate-backup-$(date +%Y%m%d-%H%M%S)"
         sudo install -m 0644 "$tmp" /etc/crypttab
         rm -f -- "$tmp"
         if command -v restorecon >/dev/null; then sudo restorecon /etc/crypttab; fi
     }
     # Only delete entries managed by this recipe, not arbitrary PAM rules.
     clean_sddm() {
         local tmp
         [[ -f "$SDDM_PAM" ]] || return 0
         if ! sudo grep -Fqx "$MARKER" "$SDDM_PAM"; then return 0; fi
         tmp="$(mktemp)"
         if ! sudo awk -v mark="$MARKER" '
             $0 == mark {
                 if (getline nextline <= 0 || nextline != "auth sufficient pam_u2f.so cue interactive pinverification=1") exit 2
                 next
             }
             {print}
         ' "$SDDM_PAM" > "$tmp"; then
             rm -f -- "$tmp"
             die "SDDM U2F block is unexpectedly modified; refusing to edit"
         fi
         sudo cp -a "$SDDM_PAM" "${SDDM_PAM}.agate-backup-$(date +%Y%m%d-%H%M%S)"
         sudo install -m 0644 "$tmp" "$SDDM_PAM"
         rm -f -- "$tmp"
         if [[ -f /usr/lib/pam.d/sddm ]] && sudo cmp -s "$SDDM_PAM" /usr/lib/pam.d/sddm; then
             sudo rm -f "$SDDM_PAM" # allow vendor PAM updates again
         fi
         if [[ -f "$SDDM_PAM" ]] && command -v restorecon >/dev/null; then sudo restorecon "$SDDM_PAM"; fi
     }
     authselect_feature() {
         local verb="$1" feature="$2"
         if [[ "$verb" == enable ]] && ! sudo authselect is-feature-enabled "$feature" >/dev/null 2>&1; then
             sudo authselect enable-feature "$feature" -b
         elif [[ "$verb" == disable ]] && sudo authselect is-feature-enabled "$feature" >/dev/null 2>&1; then
             sudo authselect disable-feature "$feature" -b
         fi
     }
     require_mapping() {
         [[ -s "$KEY_FILE" ]] || die "register a YubiKey first: ujust yubikey register"
     }
     case "$action" in
         ""|help) help ;;
         status)
             printf 'PAM mapping: %s\n' "$( [[ -s "$KEY_FILE" ]] && echo present || echo missing )"
             if command -v authselect >/dev/null; then
                 authselect current || true
             fi
             if [[ -f "$SDDM_PAM" ]] && grep -Fqx "$MARKER" "$SDDM_PAM"; then
                 echo 'SDDM login: Agate-managed U2F enabled'
             else
                 echo 'SDDM login: no Agate-managed U2F rule'
             fi
             if [[ -r /etc/crypttab ]]; then grep -n 'fido2-device=auto' /etc/crypttab || true; fi
             ;;
         register|add)
             need pamu2fcfg mktemp
             mkdir -p "$(dirname "$KEY_FILE")"
             umask 077
             tmp="$(mktemp "$(dirname "$KEY_FILE")/.u2f_keys.XXXXXX")"
             trap 'rm -f -- "$tmp"' EXIT
             if [[ "$action" == register ]]; then
                 if [[ -e "$KEY_FILE" ]]; then
                     echo "warning: existing key mappings will be replaced."
                     read -r -p "Type REPLACE to continue: " answer
                     [[ "$answer" == REPLACE ]] || die "cancelled"
                     cp -p "$KEY_FILE" "$KEY_FILE.bak.$(date +%Y%m%d-%H%M%S)"
                 fi
                 pamu2fcfg -N > "$tmp" # require FIDO2 PIN
             else
                 require_mapping
                 [[ $(wc -l < "$KEY_FILE") -eq 1 ]] || die "unexpected mapping format; refusing append"
                 existing="$(cat "$KEY_FILE")"
                 [[ "$existing" == "$(id -un):"* ]] || die "mapping belongs to a different user"
                 token="$(pamu2fcfg -n -N)"
                 printf '%s:%s\n' "$existing" "$token" > "$tmp"
             fi
             [[ -s "$tmp" ]] || die "registration returned no mapping"
             mv -f -- "$tmp" "$KEY_FILE"
             echo "YubiKey mapping saved: $KEY_FILE"
             ;;
         remove-keys)
             [[ -e "$KEY_FILE" ]] || { echo 'No mapping exists.'; exit 0; }
             if command -v authselect >/dev/null && authselect is-feature-enabled with-pam-u2f >/dev/null 2>&1; then
                 die "disable global U2F before removing keys"
             fi
             if [[ -f "$SDDM_PAM" ]] && grep -q 'pam_u2f\\.so' "$SDDM_PAM"; then
                 die "disable SDDM U2F before removing keys (including legacy rules)"
             fi
             read -r -p 'Type REMOVE to delete all local mappings: ' answer
             [[ "$answer" == REMOVE ]] || die 'cancelled'
             rm -f -- "$KEY_FILE"
             echo 'Local YubiKey mappings removed.'
             ;;
         global|login|disable)
             need sudo authselect
             root
             sudo authselect check || die "authselect configuration has local modifications; resolve first"
             if [[ "$action" != disable ]]; then require_mapping; fi
             if [[ "$action" == global ]]; then
                 clean_sddm
                 if [[ -f "$SDDM_PAM" ]] && sudo grep -q 'pam_u2f\\.so' "$SDDM_PAM"; then
                     die "unmanaged SDDM pam_u2f rule found; review it first"
                 fi
                 authselect_feature disable with-pam-u2f-2fa
                 authselect_feature enable with-pam-u2f
                 echo 'Global U2F enabled; keep password fallback tested.'
             else
                 authselect_feature disable with-pam-u2f
                 authselect_feature disable with-pam-u2f-2fa
                 clean_sddm
                 if [[ "$action" == login ]]; then
                     if [[ ! -f "$SDDM_PAM" ]]; then
                         [[ -f /usr/lib/pam.d/sddm ]] || die 'SDDM PAM source not found'
                         sudo install -m 0644 /usr/lib/pam.d/sddm "$SDDM_PAM"
                     fi
                     if sudo grep -q 'pam_u2f\\.so' "$SDDM_PAM"; then
                         die 'unmanaged pam_u2f rule present in SDDM; review it first'
                     fi
                     tmp="$(mktemp)"
                     sudo awk -v marker="$MARKER" '
                         /^auth[[:space:]]/ && !added {
                             print marker
                             print "auth sufficient pam_u2f.so cue interactive pinverification=1"
                             added=1
                         }
                         {print}
                         END {if (!added) exit 2}
                     ' "$SDDM_PAM" > "$tmp" || { rm -f "$tmp"; die 'no auth rules in SDDM PAM'; }
                     sudo cp -a "$SDDM_PAM" "${SDDM_PAM}.agate-backup-$(date +%Y%m%d-%H%M%S)"
                     sudo install -m 0644 "$tmp" "$SDDM_PAM"
                     rm -f "$tmp"
                     if command -v restorecon >/dev/null; then sudo restorecon "$SDDM_PAM"; fi
                     echo 'SDDM-only U2F enabled; KDE lockscreen unchanged.'
                 else
                     echo 'Agate-managed U2F PAM disabled.'
                     if [[ -f "$SDDM_PAM" ]] && sudo grep -q 'pam_u2f\\.so' "$SDDM_PAM"; then
                         echo 'warning: unmanaged SDDM U2F rules still exist.' >&2
                     fi
                 fi
             fi
             ;;
         luks-enroll|luks-remove)
             need sudo cryptsetup systemd-cryptenroll blkid awk readlink
             root
             select_luks "$target"
             # Must identify an unambiguous crypttab entry before changing LUKS slots.
             sudo awk -v uuid="$UUID" -v dev="$DEVICE" '
                 /^[[:space:]]*(#|$)/ {next}
                 ($2 == "UUID=" uuid || $2 == "/dev/disk/by-uuid/" uuid || $2 == dev) {found++}
                 END {if (found != 1) exit 1}
             ' /etc/crypttab || die "no unique crypttab entry for $DEVICE"
             if [[ "$action" == luks-enroll ]]; then
                 sudo install -d -m 0700 /root/agate-luks-backups
                 backup="/root/agate-luks-backups/${UUID}-$(date +%Y%m%d-%H%M%S).img"
                 sudo cryptsetup luksHeaderBackup "$DEVICE" --header-backup-file "$backup"
                 echo "LUKS header backup: $backup"
                 echo 'Keep a working passphrase and copy the header backup off this disk.'
                 sudo systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=yes "$DEVICE"
                 update_crypttab add
                 echo 'FIDO2 enrolled; verify initramfs support before rebooting.'
             else
                 echo "WARNING: this removes ALL FIDO2 enrollments from $DEVICE"
                 read -r -p 'Type WIPE to continue: ' answer
                 [[ "$answer" == WIPE ]] || die 'cancelled'
                 update_crypttab remove
                 sudo systemd-cryptenroll --wipe-slot=fido2 "$DEVICE"
                 echo 'FIDO2 enrollments removed.'
             fi
             ;;
         *) die "unknown action '$action' (run ujust yubikey for help)" ;;
     esac
