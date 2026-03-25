# global configuration with environment variable fallbacks

HOME_DIR := env_var("HOME")
TRACKED_FILE := env_var_or_default("DOTFILES_TRACKED", HOME_DIR + "/.bin/tracked")
TRACKED_ENC_FILE := env_var_or_default("DOTFILES_TRACKED_ENC", HOME_DIR + "/.bin/tracked_encrypted")
BOOTSTRAP_DIR := env_var_or_default("DOTFILES_BOOTSTRAP_DIR", HOME_DIR + "/.bin/bootstrap.d")
SSH_KEY_PATH := env_var_or_default("DOTFILES_SSH_KEY", HOME_DIR + "/.ssh/ssh_gitlab")
SKIP_BOOTSTRAP := env_var_or_default("SKIP_BOOTSTRAP", "0")
AGE_PASS := env_var_or_default("DOTFILES_AGE_PASS", "")

# bootstraps dotfiles from private gitlab repository
dotfiles-setup:
    #!/usr/bin/env bash
    mkdir -p ~/.ssh ~/.config/chezmoi ~/.config/systemd/user

    # uses existing ssh key if available
    if [ ! -f "{{ SSH_KEY_PATH }}" ]; then
        echo "Paste your GitLab SSH private key and press Ctrl+D:"
        cat > "{{ SSH_KEY_PATH }}"
        chmod 600 "{{ SSH_KEY_PATH }}"
    else
        echo "Using existing SSH key at {{ SSH_KEY_PATH }}"
    fi

    ssh-keygen -y -f "{{ SSH_KEY_PATH }}" > "{{ SSH_KEY_PATH }}.pub"
    ssh-keyscan gitlab.com >> ~/.ssh/known_hosts 2>/dev/null

    GIT_SSH_COMMAND="ssh -i {{ SSH_KEY_PATH }} -o IdentitiesOnly=yes" chezmoi init git@gitlab.com:fptbb/dotfiles.git > /dev/null 2>&1

    # isolates git repository config
    chezmoi git -- config core.sshCommand "ssh -i {{ SSH_KEY_PATH }} -o IdentitiesOnly=yes"
    chezmoi git -- config gpg.format ssh
    chezmoi git -- config user.signingkey "{{ SSH_KEY_PATH }}.pub"
    chezmoi git -- config commit.gpgsign true

    # decrypts the repository key using automated prompt if variable is set
    if [ -n "{{ AGE_PASS }}" ]; then
        if command -v expect >/dev/null 2>&1; then
            expect -c "spawn age -d -o $HOME/.config/chezmoi/key.txt $HOME/.local/share/chezmoi/age-private-key.enc; expect \"Enter passphrase:\"; send \"{{ AGE_PASS }}\r\"; expect eof" > /dev/null 2>&1
        else
            echo "warning: expect is required for non-interactive decryption. falling back to interactive prompt."
            age -d -o ~/.config/chezmoi/key.txt ~/.local/share/chezmoi/age-private-key.enc
        fi
    else
        age -d -o ~/.config/chezmoi/key.txt ~/.local/share/chezmoi/age-private-key.enc
    fi
    chmod 600 ~/.config/chezmoi/key.txt

    chezmoi apply --non-interactive > /dev/null 2>&1

    # re-creates the systemd sync services
    printf "[Unit]\nDescription=Sync dotfiles and discover new files\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/ujust dotfiles-sync\nRuntimeMaxSec=300\nStandardOutput=journal\nStandardError=journal\n" > ~/.config/systemd/user/dotfiles-upload.service
    printf "[Unit]\nDescription=Run dotfiles sync periodically\n\n[Timer]\nOnBootSec=4h\nOnUnitActiveSec=4h\n\n[Install]\nWantedBy=timers.target\n" > ~/.config/systemd/user/dotfiles-upload.timer

    chmod 644 ~/.config/systemd/user/dotfiles-upload.*
    systemctl --user daemon-reload
    systemctl --user enable --now dotfiles-upload.timer

    echo "Setup complete. Services created and timer enabled."

    # triggers post-setup scripts
    /usr/bin/ujust dotfiles-bootstrap

# executes numerical shell scripts after setup
dotfiles-bootstrap:
    #!/usr/bin/env bash
    if [ "{{ SKIP_BOOTSTRAP }}" = "1" ] || [ "{{ SKIP_BOOTSTRAP }}" = "true" ]; then
        echo "Skipping bootstrap due to SKIP_BOOTSTRAP variable."
        exit 0
    fi

    if [ -d "{{ BOOTSTRAP_DIR }}" ]; then
        echo "Running bootstrap scripts from {{ BOOTSTRAP_DIR }}..."
        # executes .sh files in alphabetical order
        for script in $(find "{{ BOOTSTRAP_DIR }}" -maxdepth 1 -type f -name "*.sh" | sort); do
            if [ -x "$script" ]; then
                echo "Executing $(basename "$script")..."
                "$script"
            else
                echo "Skipping $(basename "$script") (not executable)"
            fi
        done
        echo "Bootstrap phase complete."
    else
        echo "No bootstrap directory found at {{ BOOTSTRAP_DIR }}."
    fi

# absorbs changes, discovers new files, and purges untracked/deleted files
dotfiles-sync:
    #!/usr/bin/env bash
    echo "Starting dotfiles sync engine..."

    TRACKED="{{ TRACKED_FILE }}"
    TRACKED_ENC="{{ TRACKED_ENC_FILE }}"

    # silences output to keep logs clean
    chezmoi re-add --non-interactive > /dev/null 2>&1

    if [ -f "$TRACKED" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi
            for expanded in $line; do
                if [ -e "$expanded" ]; then
                    chezmoi add --recursive --non-interactive "$expanded" > /dev/null 2>&1
                fi
            done
        done < "$TRACKED"
    fi

    if [ -f "$TRACKED_ENC" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi
            for expanded in $line; do
                if [ -e "$expanded" ]; then
                    chezmoi add --encrypt --recursive --non-interactive "$expanded" > /dev/null 2>&1
                fi
            done
        done < "$TRACKED_ENC"
    fi

    echo "Cleaning up orphaned and untracked files..."

    VALID_PREFIXES=(
        "$TRACKED"
        "$TRACKED_ENC"
        "$HOME/.config/chezmoi"
        "$HOME/.config/systemd/user/dotfiles-upload.service"
        "$HOME/.config/systemd/user/dotfiles-upload.timer"
    )

    for list_file in "$TRACKED" "$TRACKED_ENC"; do
        if [ -f "$list_file" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi
                for expanded in $line; do
                    VALID_PREFIXES+=("$expanded")
                done
            done < "$list_file"
        fi
    done

    chezmoi managed | while read -r tracked_path; do
        full_path="$HOME/$tracked_path"

        if [ ! -e "$full_path" ]; then
            chezmoi forget "$full_path" > /dev/null 2>&1
            continue
        fi

        is_valid=0
        for prefix in "${VALID_PREFIXES[@]}"; do
            if [[ "$full_path" == "$prefix" ]] || [[ "$full_path" == "$prefix"/* ]]; then
                is_valid=1
                break
            fi
        done

        if [ $is_valid -eq 0 ]; then
            chezmoi forget "$full_path" > /dev/null 2>&1
        fi
    done

    echo "Sync engine finished."

# appends paths to standard tracking list and opens neovim
dotfiles-add *targets:
    #!/usr/bin/env bash
    if [ -n "{{ targets }}" ]; then
        for target in {{ targets }}; do
            realpath "$target" >> "{{ TRACKED_FILE }}"
        done
        echo "Added target(s) to {{ TRACKED_FILE }}"
    fi
    ${EDITOR:-nvim} "{{ TRACKED_FILE }}"

# appends paths to encrypted tracking list and opens neovim
dotfiles-add-secret *targets:
    #!/usr/bin/env bash
    if [ -n "{{ targets }}" ]; then
        for target in {{ targets }}; do
            realpath "$target" >> "{{ TRACKED_ENC_FILE }}"
        done
        echo "Added secret(s) to {{ TRACKED_ENC_FILE }}"
    fi
    ${EDITOR:-nvim} "{{ TRACKED_ENC_FILE }}"

# bypasses tracking lists to manually add a file recursively
dotfiles-manual-add +targets:
    @chezmoi add --recursive {{ targets }}
    @echo "Manually added {{ targets }}."

# bypasses tracking lists to manually add a sensitive file
dotfiles-manual-add-secret +targets:
    @chezmoi add --encrypt --recursive {{ targets }}
    @echo "Manually added and encrypted {{ targets }}."

# fetches updates from gitlab and applies them
dotfiles-update:
    @echo "Fetching and applying updates..."
    @chezmoi update --non-interactive > /dev/null 2>&1
    @echo "System is up to date."

# applies pending local changes to the system
dotfiles-apply:
    @echo "Applying local changes..."
    @chezmoi apply --non-interactive > /dev/null 2>&1
    @echo "Changes applied successfully."

# opens a shell inside the dotfiles source directory
dotfiles-cd:
    @chezmoi cd

# removes files from source state tracking
dotfiles-forget +targets:
    @chezmoi forget {{ targets }}
    @echo "Untracked {{ targets }}."

# commits and pushes local changes to gitlab
dotfiles-push message:
    @echo "Pushing changes to GitLab..."
    @chezmoi git -- add .
    @chezmoi git -- commit -m "{{ message }}" --quiet || true
    @chezmoi git -- push -u origin main --quiet
    @echo "Push complete."

# shows modified files pending sync
dotfiles-status:
    @chezmoi status

# shows line-by-line differences
dotfiles-diff:
    @chezmoi diff

# opens file in secure edit mode
dotfiles-edit target:
    @chezmoi edit {{ target }}

# tails background sync logs
dotfiles-logs:
    @journalctl --user -u dotfiles-upload.service -n 50 -f

# opens both tracking lists in neovim simultaneously
dotfiles-edit-lists:
    @${EDITOR:-nvim} -p {{ TRACKED_FILE }} {{ TRACKED_ENC_FILE }}
