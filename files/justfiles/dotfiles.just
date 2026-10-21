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
LOG_HELPERS := '''
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BLUE=$'\033[1;34m'
    C_CYAN=$'\033[1;36m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
else
    C_RESET=""
    C_BLUE=""
    C_CYAN=""
    C_GREEN=""
    C_YELLOW=""
fi

log_section() {
    printf '%b\n' "${C_BLUE}󰆍 $*${C_RESET}"
}

log_step() {
    printf '%b\n' "${C_CYAN}  󰧑 $*${C_RESET}"
}

log_success() {
    printf '%b\n' "${C_GREEN}   $*${C_RESET}"
}

log_warn() {
    printf '%b\n' "${C_YELLOW}   $*${C_RESET}"
}

log_error() {
    printf '%b\n' "${C_YELLOW}   $*${C_RESET}"
}

log_done() {
    printf '%b\n' "${C_GREEN}󰄬 $*${C_RESET}"
}
'''

# bootstraps dotfiles from private repository
dotfiles-setup:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Bootstrapping dotfiles..."
    mkdir -p ~/.ssh ~/.config/chezmoi

    # ensures dependencies are available
    log_section "Checking required tools..."
    for cmd in age chezmoi; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            if command -v brew >/dev/null 2>&1; then
                log_warn "$cmd not found. Installing via Homebrew..."
                brew install "$cmd"
                log_success "$cmd installed."
            else
                log_error "$cmd is not installed and Homebrew was not found."
                log_warn "Please install $cmd manually to continue."
                exit 1
            fi
        else
            log_success "$cmd is available."
        fi
    done

    # uses existing ssh key if available
    if [ ! -f "{{ SSH_KEY_PATH }}" ]; then
        log_warn "SSH key not found at {{ SSH_KEY_PATH }}."
        log_step "Paste your SSH private key. Input is hidden; press Enter, then Ctrl+D when finished."

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
        log_success "Using existing SSH key at {{ SSH_KEY_PATH }}."
    fi

    log_step "Generating public key from the SSH private key..."
    ssh-keygen -y -f "{{ SSH_KEY_PATH }}" > "{{ SSH_KEY_PATH }}.pub"

    # extracts domain from repo url to scan host keys
    DOMAIN=$(echo "{{ REPO_URL }}" | sed -e 's/.*@//' -e 's/:.*//')
    log_step "Scanning SSH host key for $DOMAIN..."
    ssh-keyscan "$DOMAIN" >> ~/.ssh/known_hosts 2>/dev/null

    log_section "Initializing chezmoi repository..."
    GIT_SSH_COMMAND="ssh -i {{ SSH_KEY_PATH }} -o IdentitiesOnly=yes" chezmoi init {{ REPO_URL }}

    # isolates git repository config
    log_step "Configuring chezmoi Git settings..."
    chezmoi git -- config core.sshCommand "ssh -i {{ SSH_KEY_PATH }} -o IdentitiesOnly=yes"
    chezmoi git -- config gpg.format ssh
    chezmoi git -- config user.signingkey "{{ SSH_KEY_PATH }}.pub"
    chezmoi git -- config commit.gpgsign true
    chezmoi git -- config push.autoSetupRemote true

    # decrypts the repository key using automated prompt if variable is set
    log_section "Decrypting age identity..."
    if [ -n "{{ AGE_PASS }}" ]; then
        if command -v expect >/dev/null 2>&1; then
            log_step "Using non-interactive passphrase entry with expect..."
            expect -c "spawn age -d -o $HOME/.config/chezmoi/.age-private-key.txt $HOME/.local/share/chezmoi/dot_bin/dot_age-private-key.enc; expect \"Enter passphrase:\"; send \"{{ AGE_PASS }}\r\"; expect eof"
        else
            log_warn "expect is unavailable; falling back to the interactive prompt."
            age -d -o ~/.config/chezmoi/.age-private-key.txt ~/.local/share/chezmoi/dot_bin/dot_age-private-key.enc
        fi
    else
        log_step "Waiting for interactive decryption..."
        age -d -o ~/.config/chezmoi/.age-private-key.txt ~/.local/share/chezmoi/dot_bin/dot_age-private-key.enc
    fi
    chmod 600 ~/.config/chezmoi/.age-private-key.txt

    log_section "Applying dotfiles..."
    chezmoi apply --force

    # prompts user for background sync service activation
    echo ""
    read -p "Do you want to enable the automatic background sync timer? [y/N] " ENABLE_TIMER
    if [[ "$ENABLE_TIMER" =~ ^[Yy]$ ]]; then
        log_step "Enabling dotfiles-upload.timer..."
        systemctl --user daemon-reload
        systemctl --user enable --now dotfiles-upload.timer
        log_done "Setup complete. Background sync service enabled."
    else
        log_done "Setup complete. Background sync skipped."
    fi

    # triggers post-setup scripts
    log_section "Running post-setup bootstrap hooks..."
    /usr/bin/ujust dotfiles-bootstrap

# executes numerical shell scripts after setup
dotfiles-bootstrap:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Running bootstrap scripts..."
    if [ "{{ SKIP_BOOTSTRAP }}" = "1" ] || [ "{{ SKIP_BOOTSTRAP }}" = "true" ]; then
        log_warn "Skipping bootstrap due to SKIP_BOOTSTRAP."
        exit 0
    fi

    if [ -d "{{ BOOTSTRAP_DIR }}" ]; then
        log_step "Scanning {{ BOOTSTRAP_DIR }}..."
        # executes .sh files in alphabetical order
        for script in $(find "{{ BOOTSTRAP_DIR }}" -maxdepth 1 -type f -name "*.sh" | sort); do
            if [ -x "$script" ]; then
                log_step "Executing $(basename "$script")..."
                "$script"
                log_success "Finished $(basename "$script")."
            else
                log_warn "Skipping $(basename "$script") because it is not executable."
            fi
        done
        log_done "Bootstrap phase complete."
    else
        log_warn "No bootstrap directory found at {{ BOOTSTRAP_DIR }}."
    fi

# absorbs changes, discovers new files, and purges untracked/deleted files
dotfiles-sync:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Delegating to dotfiles sync engine..."
    DOTFILES_TRACKED="{{ TRACKED_FILE }}" \
    DOTFILES_TRACKED_ENC="{{ TRACKED_ENC_FILE }}" \
    dotfiles-sync

# appends missing paths to standard tracking list and opens editor when new entries are added
dotfiles-add *targets:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    mkdir -p "$(dirname "{{ TRACKED_FILE }}")"
    touch "{{ TRACKED_FILE }}"
    home_path=$(realpath "$HOME")
    added_any=0
    log_section "Updating tracked paths..."

    if [ -n "{{ targets }}" ]; then
        for target in {{ targets }}; do
            abs_path=$(realpath "$target")
            if [[ "$abs_path" == "$home_path"/* ]]; then
                rel_path="${abs_path#$home_path/}"
                if grep -Fxq "$rel_path" "{{ TRACKED_FILE }}"; then
                    log_warn "$rel_path is already present in {{ TRACKED_FILE }}."
                else
                    echo "$rel_path" >> "{{ TRACKED_FILE }}"
                    log_success "Added $rel_path to {{ TRACKED_FILE }}."
                    added_any=1
                fi
            else
                log_warn "Skipping '$target': path must be inside your home directory."
            fi
        done
    fi

    if [ -z "{{ targets }}" ] || [ "$added_any" -eq 1 ]; then
        log_step "Opening {{ TRACKED_FILE }} in ${EDITOR:-nvim}..."
        ${EDITOR:-nvim} "{{ TRACKED_FILE }}"
    else
        log_done "No new tracked paths were added."
    fi

# appends missing paths to encrypted tracking list and opens editor when new entries are added
dotfiles-add-secret *targets:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    mkdir -p "$(dirname "{{ TRACKED_ENC_FILE }}")"
    touch "{{ TRACKED_ENC_FILE }}"
    home_path=$(realpath "$HOME")
    added_any=0
    log_section "Updating encrypted tracked paths..."

    if [ -n "{{ targets }}" ]; then
        for target in {{ targets }}; do
            abs_path=$(realpath "$target")
            if [[ "$abs_path" == "$home_path"/* ]]; then
                rel_path="${abs_path#$home_path/}"
                if grep -Fxq "$rel_path" "{{ TRACKED_ENC_FILE }}"; then
                    log_warn "$rel_path is already present in {{ TRACKED_ENC_FILE }}."
                else
                    echo "$rel_path" >> "{{ TRACKED_ENC_FILE }}"
                    log_success "Added secret $rel_path to {{ TRACKED_ENC_FILE }}."
                    added_any=1
                fi
            else
                log_warn "Skipping '$target': path must be inside your home directory."
            fi
        done
    fi

    if [ -z "{{ targets }}" ] || [ "$added_any" -eq 1 ]; then
        log_step "Opening {{ TRACKED_ENC_FILE }} in ${EDITOR:-nvim}..."
        ${EDITOR:-nvim} "{{ TRACKED_ENC_FILE }}"
    else
        log_done "No new encrypted tracked paths were added."
    fi

# bypasses tracking lists to manually track a file recursively
dotfiles-manual-add +targets:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Manually adding paths..."
    log_step "Adding {{ targets }} recursively..."
    chezmoi add --recursive {{ targets }}
    log_done "Manually added {{ targets }}."

# bypasses tracking lists to manually track a sensitive file
dotfiles-manual-add-secret +targets:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Manually adding encrypted paths..."
    log_step "Adding and encrypting {{ targets }} recursively..."
    chezmoi add --encrypt --recursive {{ targets }}
    log_done "Manually added and encrypted {{ targets }}."

# fetches updates from remote and applies them
dotfiles-update:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Fetching and applying updates..."
    chezmoi update --force
    log_done "System is up to date."

# applies pending local changes to the system
dotfiles-apply:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Applying local changes..."
    chezmoi apply --force
    log_done "Changes applied successfully."

# opens a shell inside the dotfiles source directory
dotfiles-cd:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Opening a shell in the dotfiles source directory..."
    chezmoi cd

# removes files from source state tracking
dotfiles-forget +targets:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Removing tracked paths..."
    log_step "Forgetting {{ targets }}..."
    chezmoi forget --force {{ targets }}
    log_done "Untracked {{ targets }}."

# shows modified files pending sync
dotfiles-status:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Showing dotfiles status..."
    chezmoi status

# shows line-by-line differences
dotfiles-diff:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Showing dotfiles diff..."
    chezmoi diff

# opens file in secure edit mode
dotfiles-edit target:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Opening secure edit session..."
    log_step "Editing {{ target }}..."
    chezmoi edit {{ target }}

# tails background sync logs
dotfiles-logs:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Tailing background sync logs..."
    journalctl --user -u dotfiles-upload.service -n 50 -f

# opens both tracking lists in neovim simultaneously
dotfiles-edit-lists:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Opening tracking lists..."
    log_step "Launching ${EDITOR:-nvim} with both tracking files..."
    ${EDITOR:-nvim} -p {{ TRACKED_FILE }} {{ TRACKED_ENC_FILE }}

# resets the git repository history to a single commit to save space
dotfiles-clean-history:
    #!/usr/bin/env bash
    set -e
    {{ LOG_HELPERS }}
    log_section "Cleaning dotfiles repository history..."
    DOTFILES_REPO_PATH="{{ REPO_PATH }}" dotfiles-clean-history
