# Agate OS GPG and YubiKey Utilities
# default key id for operations. override via cli if needed.

DEFAULT_GPG_KEY := "D334181D1ABE834D"

# global keyservers used for searching, importing, and publishing

GPG_SERVERS := "hkps://keyserver.ubuntu.com hkps://keys.openpgp.org hkps://pgp.mit.edu hkps://keys.mailvelope.com"

# forces a restart of the gpg and smartcard stack
[group("development")]
agate-gpg-reload ARG="":
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ ARG }}" = "--help" ] || [ "{{ ARG }}" = "-h" ]; then
        echo "usage: ujust agate-gpg-reload"
        echo "forces a restart of the gpg and smartcard stack to resolve detection issues."
        exit 0
    fi

    echo "restarting smartcard daemon..."
    sudo systemctl restart pcscd.socket pcscd.service

    echo "killing gpg-agent..."
    gpgconf --kill gpg-agent

    echo "updating startup tty..."
    gpg-connect-agent updatestartuptty /bye > /dev/null

    echo "ssh keys currently exposed to the agent:"
    SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket) ssh-add -L || echo "no ssh keys detected. is the yubikey plugged in?"

    echo "reload complete."

# lists all public and secret gpg keys in the local keyring
[group("development")]
agate-gpg-list ARG="":
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ ARG }}" = "--help" ] || [ "{{ ARG }}" = "-h" ]; then
        echo "usage: ujust agate-gpg-list"
        echo "lists all public and secret keys currently stored in the local gpg keyring."
        exit 0
    fi

    echo "=== public keys ==="
    gpg --list-keys --keyid-format=LONG
    echo ""
    echo "=== secret keys ==="
    gpg --list-secret-keys --keyid-format=LONG

# imports or searches gpg keys from files, servers, stdin, or clipboard
[group("development")]
agate-gpg-import TARGET="" FLAG="":
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ TARGET }}" = "--help" ] || [ "{{ TARGET }}" = "-h" ] || [ "{{ FLAG }}" = "--help" ]; then
        echo "usage: ujust agate-gpg-import [TARGET] [--list-all]"
        echo ""
        echo "patterns:"
        echo "  ujust agate-gpg-import                 (imports keys from clipboard)"
        echo "  ujust agate-gpg-import ./keys.asc      (imports keys from physical file)"
        echo "  ujust agate-gpg-import 79BE...         (fetches key from servers and imports)"
        echo "  ujust agate-gpg-import user@email.com  (searches and imports via email)"
        echo "  ujust agate-gpg-import 79BE... --list-all  (searches ALL servers without importing)"
        exit 0
    fi

    TARGET_ARG="{{ TARGET }}"
    LIST_ONLY=0

    # checks for the list-all flag in either argument position
    if [ "{{ TARGET }}" = "--list-all" ] || [ "{{ FLAG }}" = "--list-all" ]; then
        LIST_ONLY=1
        [ "{{ TARGET }}" = "--list-all" ] && TARGET_ARG="{{ FLAG }}"
    fi

    show_and_import() {
        local DATA="$1"
        echo "=== key details ===" >&2
        printf "%s" "$DATA" | gpg --show-keys || true
        echo "===================" >&2
        printf "%s" "$DATA" | gpg --import
    }

    if [ -n "$TARGET_ARG" ] && [ -f "$TARGET_ARG" ]; then
        [ $LIST_ONLY -eq 1 ] && { gpg --show-keys "$TARGET_ARG"; exit 0; }
        INPUT_DATA=$(cat "$TARGET_ARG")
        show_and_import "$INPUT_DATA"
        exit 0
    fi

    CLEAN_TARGET=$(echo "$TARGET_ARG" | sed -e 's/ //g' -e 's/^0x//i')

    if [[ "$CLEAN_TARGET" =~ ^[0-9a-fA-F]{8,40}$ ]] || [[ "$TARGET_ARG" == *"@"* ]]; then
        MODE_DESC="importing"
        [ $LIST_ONLY -eq 1 ] && MODE_DESC="listing"

        echo "mode: $MODE_DESC | target: $TARGET_ARG" >&2

        SUCCESS=0
        for SERVER in {{ GPG_SERVERS }}; do
            echo "querying $SERVER..." >&2
            set +e

            if [ $LIST_ONLY -eq 1 ]; then
                # uses --batch and redirects /dev/null to prevent gpg from waiting for input
                gpg --batch --no-tty --keyserver-options timeout=10 --keyserver "$SERVER" --search-keys "$TARGET_ARG" < /dev/null 2>/dev/null
                GPG_EXIT=$?
            else
                IMPORT_OUT=$(gpg --keyserver-options timeout=10 --keyserver "$SERVER" --recv-keys "$CLEAN_TARGET" 2>&1)
                GPG_EXIT=$?
            fi

            stty sane < /dev/tty || true
            set -e

            if [ $GPG_EXIT -eq 0 ]; then
                [ $LIST_ONLY -eq 0 ] && { echo "success: key imported from $SERVER." >&2; SUCCESS=1; break; }
                SUCCESS=1 
            else
                [ $LIST_ONLY -eq 0 ] && echo "warning: key not found or lacks user ID on $SERVER." >&2
            fi
        done

        if [ $SUCCESS -eq 0 ]; then
            echo "error: no valid results found on any known servers." >&2
            exit 1
        fi

        if [ $LIST_ONLY -eq 0 ] && [[ "$CLEAN_TARGET" =~ ^[0-9a-fA-F]{8,40}$ ]]; then
            echo "=== imported key metadata ===" >&2
            gpg --list-keys "$CLEAN_TARGET"
        fi
        exit 0
    fi

    if [ -n "$TARGET_ARG" ] && [ "$LIST_ONLY" -eq 0 ]; then
        echo "error: '$TARGET_ARG' is not a file, key id, or email." >&2
        exit 1
    fi

    if [ -t 0 ]; then
        if ! command -v wl-paste >/dev/null 2>&1; then
            echo "error: wl-paste is missing." >&2
            exit 1
        fi
        INPUT_DATA=$(wl-paste)
        echo "processing keys from clipboard..." >&2
    else
        INPUT_DATA=$(cat)
    fi

    if [ $LIST_ONLY -eq 1 ]; then
        printf "%s" "$INPUT_DATA" | gpg --show-keys
    else
        show_and_import "$INPUT_DATA"
    fi

# interactively deletes a gpg key from the local keyring
[group("development")]
agate-gpg-delete ARG="":
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ ARG }}" = "--help" ] || [ "{{ ARG }}" = "-h" ]; then
        echo "usage: ujust agate-gpg-delete"
        echo "launches an interactive menu to safely delete public and secret keys."
        exit 0
    fi

    mapfile -t GPG_KEYS < <(gpg --list-keys --with-colons 2>/dev/null | grep '^pub:' | cut -d':' -f5)

    if [ ${#GPG_KEYS[@]} -eq 0 ]; then
        echo "error: no gpg keys found in keyring." >&2
        exit 1
    fi

    echo "select a key to delete:" >&2
    for i in "${!GPG_KEYS[@]}"; do
        KEY_EMAIL=$(gpg --list-keys "${GPG_KEYS[$i]}" 2>/dev/null | grep 'uid' | grep -o '<.*>' | head -n 1 || true)
        echo "$i) ${GPG_KEYS[$i]} $KEY_EMAIL" >&2
    done

    printf "select key index (or press enter to cancel): " >&2
    read -r KEY_INDEX < /dev/tty

    if [ -z "$KEY_INDEX" ]; then
        echo "operation cancelled." >&2
        exit 0
    fi

    if [[ ! "$KEY_INDEX" =~ ^[0-9]+$ ]] || [ "$KEY_INDEX" -ge "${#GPG_KEYS[@]}" ]; then
        echo "error: invalid selection." >&2
        exit 1
    fi

    SELECTED_KEY="${GPG_KEYS[$KEY_INDEX]}"

    echo "warning: you are about to delete the key $SELECTED_KEY." >&2
    printf "type 'yes' to confirm: " >&2
    read -r CONFIRM < /dev/tty

    if [ "$CONFIRM" != "yes" ]; then
        echo "operation cancelled." >&2
        exit 0
    fi

    # checks for associated secret key and handles mandatory sequenced deletion
    if gpg --list-secret-keys "$SELECTED_KEY" >/dev/null 2>&1; then
        echo "secret key detected. removing secret key first..." >&2
        gpg --batch --yes --delete-secret-keys "$SELECTED_KEY"
    fi

    echo "removing public key..." >&2
    gpg --batch --yes --delete-keys "$SELECTED_KEY"
    echo "success: key $SELECTED_KEY removed from keyring." >&2

# interactively modifies a gpg key (trust level, expiration, subkeys)
[group("development")]
agate-gpg-edit ARG="":
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ ARG }}" = "--help" ] || [ "{{ ARG }}" = "-h" ]; then
        echo "usage: ujust agate-gpg-edit"
        echo "launches an interactive menu to edit key properties using the native gpg prompt."
        exit 0
    fi

    mapfile -t GPG_KEYS < <(gpg --list-keys --with-colons 2>/dev/null | grep '^pub:' | cut -d':' -f5)

    if [ ${#GPG_KEYS[@]} -eq 0 ]; then
        echo "error: no gpg keys found in keyring." >&2
        exit 1
    fi

    echo "select a key to edit:" >&2
    for i in "${!GPG_KEYS[@]}"; do
        KEY_EMAIL=$(gpg --list-keys "${GPG_KEYS[$i]}" 2>/dev/null | grep 'uid' | grep -o '<.*>' | head -n 1 || true)
        echo "$i) ${GPG_KEYS[$i]} $KEY_EMAIL" >&2
    done

    printf "select key index (or press enter to cancel): " >&2
    read -r KEY_INDEX < /dev/tty

    if [ -z "$KEY_INDEX" ]; then
        echo "operation cancelled." >&2
        exit 0
    fi

    if [[ ! "$KEY_INDEX" =~ ^[0-9]+$ ]] || [ "$KEY_INDEX" -ge "${#GPG_KEYS[@]}" ]; then
        echo "error: invalid selection." >&2
        exit 1
    fi

    SELECTED_KEY="${GPG_KEYS[$KEY_INDEX]}"

    echo "launching gpg editor for $SELECTED_KEY. type 'help' for available commands or 'quit' to exit." >&2

    set +e
    # routes standard input explicitly to tty to allow interactive editing shell
    gpg --edit-key "$SELECTED_KEY" < /dev/tty

    # restores terminal state in case gpg scrambled it
    stty sane < /dev/tty || true
    set -e

# extracts the public key and copies it to the wayland clipboard or stdout
[group("development")]
agate-gpg-export-pub TARGET_KEY=DEFAULT_GPG_KEY:
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ TARGET_KEY }}" = "--help" ] || [ "{{ TARGET_KEY }}" = "-h" ]; then
        echo "usage: ujust agate-gpg-export-pub [TARGET_KEY]"
        echo ""
        echo "patterns:"
        echo "  ujust agate-gpg-export-pub         (exports default key to clipboard)"
        echo "  ujust agate-gpg-export-pub select  (prompts for key selection, exports to clipboard)"
        exit 0
    fi

    ACTIVE_KEY="{{ TARGET_KEY }}"

    # handles interactive public key selection reading directly from tty
    if [ "$ACTIVE_KEY" = "select" ]; then
        mapfile -t GPG_KEYS < <(gpg --list-keys --with-colons 2>/dev/null | grep '^pub:' | cut -d':' -f5)

        if [ ${#GPG_KEYS[@]} -eq 0 ]; then
            echo "error: no public gpg keys found." >&2
            exit 1
        fi

        echo "available public gpg keys:" >&2
        for i in "${!GPG_KEYS[@]}"; do
            KEY_EMAIL=$(gpg --list-keys "${GPG_KEYS[$i]}" 2>/dev/null | grep 'uid' | grep -o '<.*>' | head -n 1 || true)
            echo "$i) ${GPG_KEYS[$i]} $KEY_EMAIL" >&2
        done

        printf "select key index: " >&2
        read -r KEY_INDEX < /dev/tty

        if [[ ! "$KEY_INDEX" =~ ^[0-9]+$ ]] || [ "$KEY_INDEX" -ge "${#GPG_KEYS[@]}" ]; then
            echo "error: invalid selection." >&2
            exit 1
        fi
        ACTIVE_KEY="${GPG_KEYS[$KEY_INDEX]}"
    fi

    # routes output to stdout if piped
    if [ ! -t 1 ]; then
        gpg --armor --export "$ACTIVE_KEY"
    else
        if ! command -v wl-copy >/dev/null 2>&1; then
            echo "error: wl-copy is missing." >&2
            exit 1
        fi

        PUB_KEY=$(gpg --armor --export "$ACTIVE_KEY")
        printf "%s" "$PUB_KEY" | wl-copy || true

        # fallback direct injection to klipper via dbus
        if command -v qdbus6 >/dev/null 2>&1; then
            qdbus6 org.kde.klipper /klipper setClipboardContents "$PUB_KEY" >/dev/null 2>&1 || true
        elif command -v qdbus >/dev/null 2>&1; then
            qdbus org.kde.klipper /klipper setClipboardContents "$PUB_KEY" >/dev/null 2>&1 || true
        fi

        sleep 0.4
        echo "public key $ACTIVE_KEY copied to clipboard." >&2
    fi

# publishes a public key to common keyservers
[group("development")]
agate-gpg-publish TARGET_KEY=DEFAULT_GPG_KEY:
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ TARGET_KEY }}" = "--help" ] || [ "{{ TARGET_KEY }}" = "-h" ]; then
        echo "usage: ujust agate-gpg-publish [TARGET_KEY]"
        echo ""
        echo "patterns:"
        echo "  ujust agate-gpg-publish                 (publishes the default key)"
        echo "  ujust agate-gpg-publish select          (prompts for key selection to publish)"
        echo "  ujust agate-gpg-publish 79BE...         (publishes a specific key id)"
        exit 0
    fi

    ACTIVE_KEY="{{ TARGET_KEY }}"

    # handles interactive public key selection
    if [ "$ACTIVE_KEY" = "select" ]; then
        mapfile -t GPG_KEYS < <(gpg --list-keys --with-colons 2>/dev/null | grep '^pub:' | cut -d':' -f5)

        if [ ${#GPG_KEYS[@]} -eq 0 ]; then
            echo "error: no public gpg keys found." >&2
            exit 1
        fi

        echo "available public gpg keys:" >&2
        for i in "${!GPG_KEYS[@]}"; do
            KEY_EMAIL=$(gpg --list-keys "${GPG_KEYS[$i]}" 2>/dev/null | grep 'uid' | grep -o '<.*>' | head -n 1 || true)
            echo "$i) ${GPG_KEYS[$i]} $KEY_EMAIL" >&2
        done

        printf "select key index: " >&2
        read -r KEY_INDEX < /dev/tty

        if [[ ! "$KEY_INDEX" =~ ^[0-9]+$ ]] || [ "$KEY_INDEX" -ge "${#GPG_KEYS[@]}" ]; then
            echo "error: invalid selection." >&2
            exit 1
        fi
        ACTIVE_KEY="${GPG_KEYS[$KEY_INDEX]}"
    fi

    echo "publishing key $ACTIVE_KEY..." >&2

    for SERVER in {{ GPG_SERVERS }}; do
        echo "sending to $SERVER..." >&2
        set +e
        gpg --keyserver "$SERVER" --send-keys "$ACTIVE_KEY"
        GPG_EXIT=$?
        set -e

        if [ $GPG_EXIT -eq 0 ]; then
            echo "success: key sent to $SERVER." >&2
        else
            echo "warning: failed to send key to $SERVER." >&2
        fi
    done

    echo "publish operations completed." >&2
    echo "note: keys.openpgp.org requires email verification before the user id becomes publicly searchable." >&2

# generates a revocation certificate in the current folder and optionally applies it locally
[group("development")]
agate-gpg-revoke TARGET_KEY=DEFAULT_GPG_KEY:
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ TARGET_KEY }}" = "--help" ] || [ "{{ TARGET_KEY }}" = "-h" ]; then
        echo "usage: ujust agate-gpg-revoke [TARGET_KEY]"
        echo ""
        echo "patterns:"
        echo "  ujust agate-gpg-revoke                 (revokes the default key)"
        echo "  ujust agate-gpg-revoke select          (prompts for secret key selection to revoke)"
        echo "  ujust agate-gpg-revoke 79BE...         (revokes a specific key id)"
        exit 0
    fi

    ACTIVE_KEY="{{ TARGET_KEY }}"

    # handles interactive secret key selection
    if [ "$ACTIVE_KEY" = "select" ]; then
        mapfile -t GPG_KEYS < <(gpg --list-secret-keys --with-colons 2>/dev/null | grep '^sec:' | cut -d':' -f5)

        if [ ${#GPG_KEYS[@]} -eq 0 ]; then
            echo "error: no secret gpg keys found. you can only revoke keys you own." >&2
            exit 1
        fi

        echo "available secret gpg keys:" >&2
        for i in "${!GPG_KEYS[@]}"; do
            KEY_EMAIL=$(gpg --list-secret-keys "${GPG_KEYS[$i]}" 2>/dev/null | grep 'uid' | grep -o '<.*>' | head -n 1 || true)
            echo "$i) ${GPG_KEYS[$i]} $KEY_EMAIL" >&2
        done

        printf "select key index: " >&2
        read -r KEY_INDEX < /dev/tty

        if [[ ! "$KEY_INDEX" =~ ^[0-9]+$ ]] || [ "$KEY_INDEX" -ge "${#GPG_KEYS[@]}" ]; then
            echo "error: invalid selection." >&2
            exit 1
        fi
        ACTIVE_KEY="${GPG_KEYS[$KEY_INDEX]}"
    fi

    REV_FILE="REVOCATION-${ACTIVE_KEY}.asc"

    echo "generating revocation certificate for $ACTIVE_KEY..." >&2

    set +e
    # executes generation interactively
    gpg --output "$REV_FILE" --gen-revoke "$ACTIVE_KEY" < /dev/tty

    # forcefully restores terminal state to prevent carriage return bug (^M) on read
    stty sane < /dev/tty || true
    set -e

    if [ ! -f "$REV_FILE" ]; then
        echo "error: revocation certificate generation failed or was aborted." >&2
        exit 1
    fi

    echo "success: revocation certificate saved to $REV_FILE" >&2
    echo "keep this file secure. if published, it permanently invalidates the key." >&2

    printf "do you want to apply this revocation to your local keyring now? (yes/no): " >&2
    read -r CONFIRM < /dev/tty

    if [ "$CONFIRM" = "yes" ]; then
        gpg --import "$REV_FILE"
        echo "success: key $ACTIVE_KEY has been revoked locally." >&2
        echo "use 'ujust agate-gpg-publish $ACTIVE_KEY' to broadcast the revocation to keyservers." >&2
    else
        echo "local keyring left unchanged." >&2
    fi

# encrypts text dynamically from stdin, wayland clipboard, or a physical file
[group("development")]
agate-encrypt TARGET="" TARGET_KEY=DEFAULT_GPG_KEY:
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ TARGET }}" = "--help" ] || [ "{{ TARGET }}" = "-h" ] || [ "{{ TARGET_KEY }}" = "--help" ] || [ "{{ TARGET_KEY }}" = "-h" ]; then
        echo "usage: ujust agate-encrypt [TARGET] [TARGET_KEY]"
        echo ""
        echo "patterns:"
        echo "  ujust agate-encrypt                    (encrypts clipboard using default key)"
        echo "  ujust agate-encrypt select             (encrypts clipboard, prompts for key)"
        echo "  ujust agate-encrypt ./file.txt         (encrypts file using default key, outputs file.txt.asc)"
        echo "  ujust agate-encrypt ./file.txt select  (encrypts file, prompts for key)"
        echo "  echo 'data' | ujust agate-encrypt      (encrypts stdin stream using default key)"
        exit 0
    fi

    TARGET_FILE="{{ TARGET }}"
    ACTIVE_KEY="{{ TARGET_KEY }}"

    # reassigns arguments if user omitted file but requested key selection
    if [ "$TARGET_FILE" = "select" ] && [ ! -f "$TARGET_FILE" ]; then
        ACTIVE_KEY="select"
        TARGET_FILE=""
    fi

    if [ "$ACTIVE_KEY" = "select" ]; then
        mapfile -t GPG_KEYS < <(gpg --list-keys --with-colons 2>/dev/null | grep '^pub:' | cut -d':' -f5)

        if [ ${#GPG_KEYS[@]} -eq 0 ]; then
            echo "error: no public gpg keys found." >&2
            exit 1
        fi

        echo "available public gpg keys:" >&2
        for i in "${!GPG_KEYS[@]}"; do
            KEY_EMAIL=$(gpg --list-keys "${GPG_KEYS[$i]}" 2>/dev/null | grep 'uid' | grep -o '<.*>' | head -n 1 || true)
            echo "$i) ${GPG_KEYS[$i]} $KEY_EMAIL" >&2
        done

        printf "select key index: " >&2
        read -r KEY_INDEX < /dev/tty

        if [[ ! "$KEY_INDEX" =~ ^[0-9]+$ ]] || [ "$KEY_INDEX" -ge "${#GPG_KEYS[@]}" ]; then
            echo "error: invalid selection." >&2
            exit 1
        fi
        ACTIVE_KEY="${GPG_KEYS[$KEY_INDEX]}"
    fi

    # processes physical file and exits
    if [ -n "$TARGET_FILE" ]; then
        if [ ! -f "$TARGET_FILE" ]; then
            echo "error: file not found: $TARGET_FILE" >&2
            exit 1
        fi
        gpg --armor --recipient "$ACTIVE_KEY" --encrypt "$TARGET_FILE"
        echo "success: file encrypted to $TARGET_FILE.asc" >&2
        exit 0
    fi

    # safely reads input into memory from pipe or clipboard
    if [ -t 0 ]; then
        if ! command -v wl-paste >/dev/null 2>&1; then
            echo "error: wl-paste is missing." >&2
            exit 1
        fi
        INPUT_DATA=$(wl-paste)
    else
        INPUT_DATA=$(cat)
    fi

    # isolates gpg processing from streams
    ENCRYPTED_DATA=$(printf "%s" "$INPUT_DATA" | gpg --armor --recipient "$ACTIVE_KEY" --encrypt)

    # routes output to pipe or clipboard
    if [ -t 1 ]; then
        if ! command -v wl-copy >/dev/null 2>&1; then
            echo "error: wl-copy is missing." >&2
            exit 1
        fi

        printf "%s" "$ENCRYPTED_DATA" | wl-copy || true

        if command -v qdbus6 >/dev/null 2>&1; then
            qdbus6 org.kde.klipper /klipper setClipboardContents "$ENCRYPTED_DATA" >/dev/null 2>&1 || true
        elif command -v qdbus >/dev/null 2>&1; then
            qdbus org.kde.klipper /klipper setClipboardContents "$ENCRYPTED_DATA" >/dev/null 2>&1 || true
        fi

        sleep 0.4
        echo "success: encrypted text copied to clipboard." >&2
    else
        printf "%s" "$ENCRYPTED_DATA"
    fi

# clearsigns text dynamically from stdin, wayland clipboard, or a physical file
[group("development")]
agate-sign TARGET="" TARGET_KEY=DEFAULT_GPG_KEY:
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ TARGET }}" = "--help" ] || [ "{{ TARGET }}" = "-h" ] || [ "{{ TARGET_KEY }}" = "--help" ] || [ "{{ TARGET_KEY }}" = "-h" ]; then
        echo "usage: ujust agate-sign [TARGET] [TARGET_KEY]"
        echo ""
        echo "patterns:"
        echo "  ujust agate-sign                    (signs clipboard using default key)"
        echo "  ujust agate-sign select             (signs clipboard, prompts for key)"
        echo "  ujust agate-sign ./file.txt         (signs file using default key, outputs file.txt.asc)"
        echo "  ujust agate-sign ./file.txt select  (signs file, prompts for key)"
        echo "  echo 'data' | ujust agate-sign      (signs stdin stream using default key)"
        exit 0
    fi

    TARGET_FILE="{{ TARGET }}"
    ACTIVE_KEY="{{ TARGET_KEY }}"

    if [ "$TARGET_FILE" = "select" ] && [ ! -f "$TARGET_FILE" ]; then
        ACTIVE_KEY="select"
        TARGET_FILE=""
    fi

    if [ "$ACTIVE_KEY" = "select" ]; then
        mapfile -t GPG_KEYS < <(gpg --list-secret-keys --with-colons 2>/dev/null | grep '^sec:' | cut -d':' -f5)

        if [ ${#GPG_KEYS[@]} -eq 0 ]; then
            echo "error: no secret gpg keys found." >&2
            exit 1
        fi

        echo "available secret gpg keys:" >&2
        for i in "${!GPG_KEYS[@]}"; do
            KEY_EMAIL=$(gpg --list-secret-keys "${GPG_KEYS[$i]}" 2>/dev/null | grep 'uid' | grep -o '<.*>' | head -n 1 || true)
            echo "$i) ${GPG_KEYS[$i]} $KEY_EMAIL" >&2
        done

        printf "select key index: " >&2
        read -r KEY_INDEX < /dev/tty

        if [[ ! "$KEY_INDEX" =~ ^[0-9]+$ ]] || [ "$KEY_INDEX" -ge "${#GPG_KEYS[@]}" ]; then
            echo "error: invalid selection." >&2
            exit 1
        fi
        ACTIVE_KEY="${GPG_KEYS[$KEY_INDEX]}"
    fi

    if [ -n "$TARGET_FILE" ]; then
        if [ ! -f "$TARGET_FILE" ]; then
            echo "error: file not found: $TARGET_FILE" >&2
            exit 1
        fi
        gpg --armor --local-user "$ACTIVE_KEY" --clearsign "$TARGET_FILE"
        echo "success: file signed to $TARGET_FILE.asc" >&2
        exit 0
    fi

    if [ -t 0 ]; then
        if ! command -v wl-paste >/dev/null 2>&1; then
            echo "error: wl-paste is missing." >&2
            exit 1
        fi
        INPUT_DATA=$(wl-paste)
    else
        INPUT_DATA=$(cat)
    fi

    SIGNED_DATA=$(printf "%s" "$INPUT_DATA" | gpg --armor --local-user "$ACTIVE_KEY" --clearsign)

    if [ -t 1 ]; then
        if ! command -v wl-copy >/dev/null 2>&1; then
            echo "error: wl-copy is missing." >&2
            exit 1
        fi

        printf "%s" "$SIGNED_DATA" | wl-copy || true

        if command -v qdbus6 >/dev/null 2>&1; then
            qdbus6 org.kde.klipper /klipper setClipboardContents "$SIGNED_DATA" >/dev/null 2>&1 || true
        elif command -v qdbus >/dev/null 2>&1; then
            qdbus org.kde.klipper /klipper setClipboardContents "$SIGNED_DATA" >/dev/null 2>&1 || true
        fi

        sleep 0.4
        echo "success: signed text copied to clipboard." >&2
    else
        printf "%s" "$SIGNED_DATA"
    fi

# decrypts pgp data dynamically from stdin, wayland clipboard, or a physical file
[group("development")]
agate-decrypt TARGET="":
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ TARGET }}" = "--help" ] || [ "{{ TARGET }}" = "-h" ]; then
        echo "usage: ujust agate-decrypt [TARGET]"
        echo ""
        echo "patterns:"
        echo "  ujust agate-decrypt                 (decrypts clipboard to terminal/stdout)"
        echo "  ujust agate-decrypt ./file.txt.asc  (decrypts file to terminal/stdout)"
        echo "  cat data.asc | ujust agate-decrypt  (decrypts stdin stream to terminal/stdout)"
        exit 0
    fi

    TARGET_FILE="{{ TARGET }}"

    # processes physical file and prints to stdout
    if [ -n "$TARGET_FILE" ]; then
        if [ ! -f "$TARGET_FILE" ]; then
            echo "error: file not found: $TARGET_FILE" >&2
            exit 1
        fi
        gpg --decrypt "$TARGET_FILE"
        exit 0
    fi

    if [ -t 0 ]; then
        if ! command -v wl-paste >/dev/null 2>&1; then
            echo "error: wl-paste is missing." >&2
            exit 1
        fi
        INPUT_DATA=$(wl-paste)
        echo "decrypting clipboard contents..." >&2
        echo "--------------------------------" >&2
    else
        INPUT_DATA=$(cat)
    fi

    DECRYPTED_DATA=$(printf "%s" "$INPUT_DATA" | gpg --decrypt)

    if [ -t 1 ]; then
        printf "%s\n" "$DECRYPTED_DATA"
        echo "--------------------------------" >&2
    else
        printf "%s" "$DECRYPTED_DATA"
    fi

# toggles git commit signing configuration between yubikey and local gpg keys
[group("development")]
agate-git-sign ARG="":
    #!/usr/bin/env bash
    set -euo pipefail

    # handles help command
    if [ "{{ ARG }}" = "--help" ] || [ "{{ ARG }}" = "-h" ]; then
        echo "usage: ujust agate-git-sign"
        echo ""
        echo "patterns:"
        echo "  ujust agate-git-sign                (launches interactive menu to select signing key)"
        exit 0
    fi

    echo "=== Git Commit Signing Configuration ==="
    echo "1) Use YubiKey GPG (D334181D1ABE834D)"
    echo "2) Use Local GPG Key"
    echo "3) Disable Commit Signing"
    echo "4) Exit"

    set +e
    read -p "choose an option: " OPTION < /dev/tty
    set -e

    case $OPTION in
        1)
            git config --global gpg.format openpgp
            git config --global user.signingkey D334181D1ABE834D
            git config --global commit.gpgsign true
            echo "git configured to sign commits using yubikey gpg key."
            ;;
        2)
            mapfile -t GPG_KEYS < <(gpg --list-secret-keys --with-colons 2>/dev/null | grep '^sec:' | cut -d':' -f5)

            if [ ${#GPG_KEYS[@]} -eq 0 ]; then
                echo "error: no secret gpg keys found in ~/.gnupg/"
                exit 1
            fi

            echo "available local gpg keys:"
            for i in "${!GPG_KEYS[@]}"; do
                KEY_EMAIL=$(gpg --list-secret-keys "${GPG_KEYS[$i]}" 2>/dev/null | grep 'uid' | grep -o '<.*>' | head -n 1 || true)
                echo "$i) ${GPG_KEYS[$i]} $KEY_EMAIL"
            done

            set +e
            read -p "select key index: " KEY_INDEX < /dev/tty
            set -e

            if [[ ! "$KEY_INDEX" =~ ^[0-9]+$ ]] || [ "$KEY_INDEX" -ge "${#GPG_KEYS[@]}" ]; then
                echo "error: invalid selection."
                exit 1
            fi

            SELECTED_KEY="${GPG_KEYS[$KEY_INDEX]}"

            git config --global gpg.format openpgp
            git config --global user.signingkey "$SELECTED_KEY"
            git config --global commit.gpgsign true
            echo "git configured to sign commits using local gpg key: $SELECTED_KEY."
            ;;
        3)
            git config --global commit.gpgsign false
            echo "git commit signing disabled."
            ;;
        4)
            exit 0
            ;;
        *)
            echo "error: invalid option."
            exit 1
            ;;
    esac
