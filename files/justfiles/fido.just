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

    # enforces root privileges
    if [ "$EUID" -ne 0 ]; then
        echo "error: permission denied. run with sudo."
        exit 1
    fi

    CRYPT_LINE=$(grep -v '^#' /etc/crypttab | head -n 1 || true)
    if [ -z "$CRYPT_LINE" ]; then
        echo "error: no active luks entry found in /etc/crypttab."
        exit 1
    fi

    # extracts block device path via uuid
    DISK_UUID=$(echo "$CRYPT_LINE" | awk '{print $2}' | sed 's/UUID=//')
    DISK_PATH="/dev/disk/by-uuid/$DISK_UUID"

    if [ ! -b "$DISK_PATH" ]; then
        echo "error: block device not found for $DISK_UUID."
        exit 1
    fi

    echo "luks device identified: $DISK_PATH"
    
    # initializes safety backups
    BACKUP_IMG="/root/luks-header-backup-${DISK_UUID}.img"
    if ! cryptsetup luksHeaderBackup "$DISK_PATH" --header-backup-file "$BACKUP_IMG"; then
        echo "error: luks header backup failed."
        exit 1
    fi
    echo "luks header backed up to $BACKUP_IMG"

    cp /etc/crypttab /etc/crypttab.bak
    echo "crypttab backed up to /etc/crypttab.bak"

    echo "insert yubikey. current luks password and fido2 pin will be requested..."

    # registers hardware token in luks header
    if ! systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=yes "$DISK_PATH"; then
        echo "error: systemd-cryptenroll hardware registration failed."
        exit 1
    fi

    # applies crypttab flag preventing duplicates
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

    # enforces root privileges
    if [ "$EUID" -ne 0 ]; then
        echo "error: permission denied. run with sudo."
        exit 1
    fi

    SELECTED_DEV="{{TARGET_DEV}}"

    # handles interactive device selection if argument is empty
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
    
    # clears hardware token slots
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

# manages interactive yubikey pam authentication for kde
[group("system")]
agate-kde-setup: _agate-check-pam-deps
    #!/usr/bin/env bash
    set -euo pipefail

    # enforces root privileges
    if [ "$EUID" -ne 0 ]; then
        echo "error: permission denied. run with sudo."
        exit 1
    fi

    # resolves actual user under sudo session
    REAL_USER=${SUDO_USER:-$USER}
    USER_HOME=$(eval echo ~$REAL_USER)
    YUBI_DIR="$USER_HOME/.config/Yubico"
    KEY_FILE="$YUBI_DIR/u2f_keys"

    echo "=== kde yubikey management ==="
    echo "1) enable pam-u2f authentication (requires pin, falls back to password)"
    echo "2) disable pam-u2f authentication"
    echo "3) register primary yubikey (overwrites current keys)"
    echo "4) register additional yubikey"
    echo "5) remove all registered yubikeys"
    echo "6) exit"

    set +e
    read -p "choose an option: " OPTION
    set -e

    case $OPTION in
        1)
            # injects pinverification flag into custom authselect profile
            authselect create-profile yubikey-custom -b local --symlink-meta || true
            sed -i 's/pam_u2f.so cue/pam_u2f.so cue interactive pinverification=1/g' /etc/authselect/custom/yubikey-custom/*
            
            authselect select custom/yubikey-custom with-silent-lastlog with-mdns4 with-fingerprint with-pam-u2f --force
            echo "pam-u2f authentication enabled."
            ;;
        2)
            # restores native local profile
            authselect select local with-silent-lastlog with-mdns4 with-fingerprint --force
            echo "pam-u2f authentication disabled."
            ;;
        3)
            # drops privileges to write mapping file
            sudo -u "$REAL_USER" mkdir -p "$YUBI_DIR"
            echo "touch your yubikey now..."
            
            sudo -u "$REAL_USER" pamu2fcfg > "$KEY_FILE"
            echo "primary yubikey registered successfully."
            ;;
        4)
            if [ ! -f "$KEY_FILE" ]; then
                echo "error: primary key missing. run option 3 first."
                exit 1
            fi
            echo "touch your new yubikey now..."
            
            sudo -u "$REAL_USER" pamu2fcfg -n >> "$KEY_FILE"
            echo "additional yubikey registered."
            ;;
        5)
            # clears mapping file
            sudo -u "$REAL_USER" rm -f "$KEY_FILE"
            echo "all keys have been removed."
            ;;
        6)
            exit 0
            ;;
        *)
            echo "error: invalid option."
            exit 1
            ;;
    esac