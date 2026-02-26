# Agate OS YubiKey and LUKS Management
#
# BlueBuild Image Requirements (recipe.yml):
# modules:
#   - type: rpm-ostree
#     install:
#       - libfido2
#       - fido2-tools
#       - pam-u2f
#   - type: script
#     snippets:
#       - "mkdir -p /usr/lib/dracut.conf.d/"
#       - "echo 'add_dracutmodules+=\" fido2 \"' > /usr/lib/dracut.conf.d/10-fido2.conf"
#
# LiveUSB Recovery Instructions (if LUKS header/config fails):
# 1. Boot Fedora LiveUSB and elevate to root (sudo su -).
# 2. Identify encrypted partition via lsblk -f.
# 3. Wipe FIDO2 slot: systemd-cryptenroll --wipe-slot=fido2 /dev/nvme0n1pX
# 4. Unlock partition: cryptsetup luksOpen /dev/nvme0n1pX cryptroot
# 5. Mount OSTree sysroot: mkdir -p /mnt/sysroot && mount /dev/mapper/cryptroot /mnt/sysroot
# 6. Locate deployment crypttab: nano /mnt/sysroot/ostree/deploy/fedora/deploy/<deployment-id>/etc/crypttab
# 7. Remove ",fido2-device=auto" flag, save, umount /mnt/sysroot, and reboot.

# checks required luks binaries
_agate-check-luks-deps:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v systemd-cryptenroll >/dev/null 2>&1; then
        echo "error: systemd-cryptenroll is missing."
        exit 1
    fi
    if ! command -v cryptsetup >/dev/null 2>&1; then
        echo "error: cryptsetup is missing."
        exit 1
    fi

# checks required pam binaries
_agate-check-pam-deps:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v pamu2fcfg >/dev/null 2>&1; then
        echo "error: pamu2fcfg is missing. ensure pam-u2f is installed."
        exit 1
    fi
    if ! command -v authselect >/dev/null 2>&1; then
        echo "error: authselect is missing."
        exit 1
    fi

# configures yubikey for luks decryption with safety backups
[group("system")]
agate-luks-setup: _agate-check-luks-deps
    #!/usr/bin/env bash
    set -euo pipefail

    if [ "$EUID" -ne 0 ]; then
        echo "error: permission denied. run with sudo."
        exit 1
    fi

    CRYPT_LINE=$(grep -v '^#' /etc/crypttab | head -n 1 || true)
    if [ -z "$CRYPT_LINE" ]; then
        echo "error: no active luks entry found in /etc/crypttab."
        exit 1
    fi

    DISK_UUID=$(echo "$CRYPT_LINE" | awk '{print $2}' | sed 's/UUID=//')
    DISK_PATH="/dev/disk/by-uuid/$DISK_UUID"

    if [ ! -b "$DISK_PATH" ]; then
        echo "error: block device not found for $DISK_UUID."
        exit 1
    fi

    echo "luks device identified: $DISK_PATH"

    BACKUP_IMG="/root/luks-header-backup-${DISK_UUID}.img"
    if ! cryptsetup luksHeaderBackup "$DISK_PATH" --header-backup-file "$BACKUP_IMG"; then
        echo "error: luks header backup failed."
        exit 1
    fi
    echo "luks header backed up to $BACKUP_IMG"

    cp /etc/crypttab /etc/crypttab.bak
    echo "crypttab backed up to /etc/crypttab.bak"

    echo "insert yubikey. current luks password and fido2 pin will be requested..."

    if ! systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=yes "$DISK_PATH"; then
        echo "error: systemd-cryptenroll hardware registration failed."
        exit 1
    fi

    if grep -q "fido2-device=auto" /etc/crypttab; then
        echo "info: fido2-device=auto is already present in /etc/crypttab."
    else
        sed -i "s|$DISK_UUID.*|&,fido2-device=auto|" /etc/crypttab
        echo "success: /etc/crypttab updated."
    fi

    echo "setup complete."

# removes fido2 slots from luks header
[group("system")]
agate-luks-remove TARGET_DEV="": _agate-check-luks-deps
    #!/usr/bin/env bash
    set -euo pipefail

    if [ "$EUID" -ne 0 ]; then
        echo "error: permission denied. run with sudo."
        exit 1
    fi

    SELECTED_DEV="{{TARGET_DEV}}"

    # handles interactive device selection
    if [ -z "$SELECTED_DEV" ]; then
        mapfile -t LUKS_DEVICES < <(blkid -t TYPE=crypto_LUKS -o device)

        if [ ${#LUKS_DEVICES[@]} -eq 0 ]; then
            echo "error: no luks devices found."
            exit 1
        elif [ ${#LUKS_DEVICES[@]} -eq 1 ]; then
            SELECTED_DEV="${LUKS_DEVICES[0]}"
            echo "single luks device detected: $SELECTED_DEV"
        else
            echo "multiple luks devices found:"
            for i in "${!LUKS_DEVICES[@]}"; do
                echo "$i) ${LUKS_DEVICES[$i]}"
            done

            set +e
            read -p "select device index: " INDEX
            set -e

            if [[ ! "$INDEX" =~ ^[0-9]+$ ]] || [ "$INDEX" -ge "${#LUKS_DEVICES[@]}" ]; then
                echo "error: invalid selection."
                exit 1
            fi
            SELECTED_DEV="${LUKS_DEVICES[$INDEX]}"
        fi
    fi

    if [ ! -b "$SELECTED_DEV" ]; then
        echo "error: invalid device $SELECTED_DEV."
        exit 1
    fi

    echo "removing fido2 slots from $SELECTED_DEV..."

    if ! systemd-cryptenroll --wipe-slot=fido2 "$SELECTED_DEV"; then
        echo "error: fido2 slot wipe failed."
        exit 1
    fi

    # clears local crypttab flag
    if [ -f /etc/crypttab ]; then
        DEV_UUID=$(blkid -s UUID -o value "$SELECTED_DEV" || true)
        if [ -n "$DEV_UUID" ] && grep -q "$DEV_UUID" /etc/crypttab; then
            sed -i 's|,fido2-device=auto||g' /etc/crypttab
            echo "success: flag removed from local /etc/crypttab."
        fi
    fi

    echo "removal complete."

# manages interactive yubikey authentication
[group("system")]
agate-kde-setup: _agate-check-pam-deps
    #!/usr/bin/env bash
    set -euo pipefail

    if [ "$EUID" -ne 0 ]; then
        echo "error: permission denied. run with sudo."
        exit 1
    fi

    REAL_USER=${SUDO_USER:-$USER}
    USER_HOME=$(eval echo ~$REAL_USER)
    YUBI_DIR="$USER_HOME/.config/Yubico"
    KEY_FILE="$YUBI_DIR/u2f_keys"

    echo "=== KDE YubiKey Management ==="
    echo "1) Enable YubiKey everywhere (Login, Lockscreen, Sudo, App installations)"
    echo "2) Enable YubiKey for the initial Login screen only (Recommended)"
    echo "3) Disable YubiKey authentication completely"
    echo "4) Register your primary YubiKey (Erases previous keys)"
    echo "5) Register an additional YubiKey"
    echo "6) Remove all registered YubiKeys"
    echo "7) Exit"

    set +e
    read -p "choose an option: " OPTION
    set -e

    case $OPTION in
        1)
            if [ ! -f "$KEY_FILE" ]; then
                echo "error: yubikey mapping not found. run option 4 to register a key first."
                exit 1
            fi

            # clears local gui edits
            for APP in sddm kscreenlocker; do
                PAM_FILE="/etc/pam.d/$APP"
                if [ -f "$PAM_FILE" ]; then
                    sed -i '/pam_u2f\.so/d' "$PAM_FILE"
                fi
            done

            authselect create-profile yubikey-custom -b local --symlink-meta || true
            sed -i 's/pam_u2f.so cue/pam_u2f.so cue pinverification=1/g' /etc/authselect/custom/yubikey-custom/*

            authselect select custom/yubikey-custom with-silent-lastlog with-mdns4 with-fingerprint with-pam-u2f --force
            echo "global authentication enabled."
            ;;
        2)
            if [ ! -f "$KEY_FILE" ]; then
                echo "error: yubikey mapping not found. run option 4 to register a key first."
                exit 1
            fi

            # reverts global authselect profile
            authselect select local with-silent-lastlog with-mdns4 with-fingerprint --force
            if [ -d "/etc/authselect/custom/yubikey-custom" ]; then
                rm -rf /etc/authselect/custom/yubikey-custom
            fi

            # applies pin requirement exclusively to sddm
            SDDM_RULE="auth sufficient pam_u2f.so cue interactive pinverification=1"
            if [ ! -f "/etc/pam.d/sddm" ] && [ -f "/usr/lib/pam.d/sddm" ]; then
                cp "/usr/lib/pam.d/sddm" "/etc/pam.d/sddm"
            fi
            if [ -f "/etc/pam.d/sddm" ]; then
                sed -i '/pam_u2f\.so/d' "/etc/pam.d/sddm"
                awk -v rule="$SDDM_RULE" '/^auth/ && !inserted {print rule; inserted=1} 1' "/etc/pam.d/sddm" > "/etc/pam.d/sddm.tmp"
                mv "/etc/pam.d/sddm.tmp" "/etc/pam.d/sddm"
                chmod 644 "/etc/pam.d/sddm"
            fi

            # ensures kscreenlocker is completely clean from previous configurations
            if [ -f "/etc/pam.d/kscreenlocker" ]; then
                sed -i '/pam_u2f\.so/d' "/etc/pam.d/kscreenlocker"
            fi

            echo "login screen authentication enabled."
            echo "note: the kde lockscreen will continue to ask only for your standard password."
            ;;
        3)
            # clears local gui edits
            for APP in sddm kscreenlocker; do
                PAM_FILE="/etc/pam.d/$APP"
                if [ -f "$PAM_FILE" ]; then
                    sed -i '/pam_u2f\.so/d' "$PAM_FILE"
                fi
            done

            authselect select local with-silent-lastlog with-mdns4 with-fingerprint --force
            if [ -d "/etc/authselect/custom/yubikey-custom" ]; then
                rm -rf /etc/authselect/custom/yubikey-custom
            fi

            echo "authentication disabled completely."
            ;;
        4)
            sudo -u "$REAL_USER" mkdir -p "$YUBI_DIR"
            echo "enter your fido2 pin if prompted, then touch your yubikey to register..."

            sudo -u "$REAL_USER" pamu2fcfg > "$KEY_FILE"
            echo "primary yubikey registered successfully."
            ;;
        5)
            if [ ! -f "$KEY_FILE" ]; then
                echo "error: primary key missing. run option 4 first."
                exit 1
            fi
            echo "enter your fido2 pin if prompted, then touch your new yubikey to register..."

            sudo -u "$REAL_USER" pamu2fcfg -n >> "$KEY_FILE"
            echo "additional yubikey registered."
            ;;
        6)
            sudo -u "$REAL_USER" rm -f "$KEY_FILE"
            echo "all keys have been removed."
            ;;
        7)
            exit 0
            ;;
        *)
            echo "error: invalid option."
            exit 1
            ;;
    esac
