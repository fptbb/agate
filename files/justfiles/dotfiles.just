# defines global configuration with environment variable fallbacks

HOME_DIR := env_var("HOME")
TRACKED_FILE := env_var_or_default("DOTFILES_TRACKED", HOME_DIR + "/.bin/tracked")
TRACKED_ENC_FILE := env_var_or_default("DOTFILES_TRACKED_ENC", HOME_DIR + "/.bin/tracked_encrypted")
BOOTSTRAP_DIR := env_var_or_default("DOTFILES_BOOTSTRAP_DIR", HOME_DIR + "/.bin/bootstrap.d")
SSH_KEY_PATH := env_var_or_default("DOTFILES_SSH_KEY", HOME_DIR + "/.ssh/ssh_gitlab")
SKIP_BOOTSTRAP := env_var_or_default("SKIP_BOOTSTRAP", "0")
AGE_PASS := env_var_or_default("DOTFILES_AGE_PASS", "")
REPO_PATH := env_var_or_default("DOTFILES_REPO_PATH", "fptbb/dotfiles")
REPO_URL := env_var_or_default("DOTFILES_REPO_URL", "git@gitlab.com:" + REPO_PATH + ".git")

# bootstraps dotfiles from private repository
dotfiles-setup:
    #!/usr/bin/env bash
    set -e
    mkdir -p ~/.ssh ~/.config/chezmoi

    # ensures dependencies are available
    for cmd in age chezmoi; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            if command -v brew >/dev/null 2>&1; then
                echo "$cmd not found. installing via homebrew..."
                brew install "$cmd"
            else
                echo "error: $cmd is not installed and homebrew was not found."
                echo "please install $cmd manually to continue."
                exit 1
            fi
        fi
    done

    # uses existing ssh key if available
    if [ ! -f "{{ SSH_KEY_PATH }}" ]; then
        echo "Paste your SSH private key (input is hidden). Press Enter, then Ctrl+D when finished:"

        # creates or clears the file
        : > "{{ SSH_KEY_PATH }}"
        chmod 600 "{{ SSH_KEY_PATH }}"

        # reads input character by character or line by line silently
        while IFS= read -r -s line; do
            echo "$line" >> "{{ SSH_KEY_PATH }}"
        done

        # adds a final newline if the file is empty or formatted oddly
        echo "" >> "{{ SSH_KEY_PATH }}"
    else
        echo "Using existing SSH key at {{ SSH_KEY_PATH }}"
    fi

    ssh-keygen -y -f "{{ SSH_KEY_PATH }}" > "{{ SSH_KEY_PATH }}.pub"

    # extracts domain from repo url to scan host keys
    DOMAIN=$(echo "{{ REPO_URL }}" | sed -e 's/.*@//' -e 's/:.*//')
    ssh-keyscan "$DOMAIN" >> ~/.ssh/known_hosts 2>/dev/null

    GIT_SSH_COMMAND="ssh -i {{ SSH_KEY_PATH }} -o IdentitiesOnly=yes" chezmoi init {{ REPO_URL }}

    # isolates git repository config
    chezmoi git -- config core.sshCommand "ssh -i {{ SSH_KEY_PATH }} -o IdentitiesOnly=yes"
    chezmoi git -- config gpg.format ssh
    chezmoi git -- config user.signingkey "{{ SSH_KEY_PATH }}.pub"
    chezmoi git -- config commit.gpgsign true
    chezmoi git -- config push.autoSetupRemote true

    # decrypts the repository key using automated prompt if variable is set
    if [ -n "{{ AGE_PASS }}" ]; then
        if command -v expect >/dev/null 2>&1; then
            expect -c "spawn age -d -o $HOME/.config/chezmoi/.age-private-key.txt $HOME/.local/share/chezmoi/dot_bin/dot_age-private-key.enc; expect \"Enter passphrase:\"; send \"{{ AGE_PASS }}\r\"; expect eof"
        else
            echo "warning: expect is required for non-interactive decryption. falling back to interactive prompt."
            age -d -o ~/.config/chezmoi/.age-private-key.txt ~/.local/share/chezmoi/dot_bin/dot_age-private-key.enc
        fi
    else
        age -d -o ~/.config/chezmoi/.age-private-key.txt ~/.local/share/chezmoi/dot_bin/dot_age-private-key.enc
    fi
    chmod 600 ~/.config/chezmoi/.age-private-key.txt

    chezmoi apply --force

    # prompts user for background sync service activation
    echo ""
    read -p "Do you want to enable the automatic background sync timer? [y/N] " ENABLE_TIMER
    if [[ "$ENABLE_TIMER" =~ ^[Yy]$ ]]; then
        systemctl --user daemon-reload
        systemctl --user enable --now dotfiles-upload.timer
        echo "Setup complete. Background sync service enabled."
    else
        echo "Setup complete. Background sync skipped."
    fi

    # triggers post-setup scripts
    /usr/bin/ujust dotfiles-bootstrap

# executes numerical shell scripts after setup
dotfiles-bootstrap:
    #!/usr/bin/env bash
    set -e
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
    set -e
    DOTFILES_TRACKED="{{ TRACKED_FILE }}" \
    DOTFILES_TRACKED_ENC="{{ TRACKED_ENC_FILE }}" \
    dotfiles-sync

# appends paths to standard tracking list and opens neovim
dotfiles-add *targets:
    #!/usr/bin/env bash
    if [ -n "{{ targets }}" ]; then
        for target in {{ targets }}; do
            abs_path=$(realpath "$target")
            if [[ "$abs_path" == "$HOME/"* ]]; then
                rel_path="${abs_path#$HOME/}"
                echo "$rel_path" >> "{{ TRACKED_FILE }}"
                echo "Added $rel_path to {{ TRACKED_FILE }}"
            else
                echo "Skipping '$target': path must be inside your home directory."
            fi
        done
    fi
    ${EDITOR:-nvim} "{{ TRACKED_FILE }}"

# appends paths to encrypted tracking list and opens neovim
dotfiles-add-secret *targets:
    #!/usr/bin/env bash
    if [ -n "{{ targets }}" ]; then
        for target in {{ targets }}; do
            abs_path=$(realpath "$target")
            if [[ "$abs_path" == "$HOME/"* ]]; then
                rel_path="${abs_path#$HOME/}"
                echo "$rel_path" >> "{{ TRACKED_ENC_FILE }}"
                echo "Added secret $rel_path to {{ TRACKED_ENC_FILE }}"
            else
                echo "Skipping '$target': path must be inside your home directory."
            fi
        done
    fi
    ${EDITOR:-nvim} "{{ TRACKED_ENC_FILE }}"

# bypasses tracking lists to manually track a file recursively
dotfiles-manual-add +targets:
    @chezmoi add --recursive {{ targets }}
    @echo "Manually added {{ targets }}."

# bypasses tracking lists to manually track a sensitive file
dotfiles-manual-add-secret +targets:
    @chezmoi add --encrypt --recursive {{ targets }}
    @echo "Manually added and encrypted {{ targets }}."

# fetches updates from remote and applies them
dotfiles-update:
    @echo "Fetching and applying updates..."
    @chezmoi update --force
    @echo "System is up to date."

# applies pending local changes to the system
dotfiles-apply:
    @echo "Applying local changes..."
    @chezmoi apply --force
    @echo "Changes applied successfully."

# opens a shell inside the dotfiles source directory
dotfiles-cd:
    @chezmoi cd

# removes files from source state tracking
dotfiles-forget +targets:
    @chezmoi forget --force {{ targets }}
    @echo "Untracked {{ targets }}."

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

# resets the git repository history to a single commit to save space
dotfiles-clean-history:
    #!/usr/bin/env bash
    set -e
    DOTFILES_REPO_PATH="{{ REPO_PATH }}" dotfiles-clean-history
