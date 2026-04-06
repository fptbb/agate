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
    mkdir -p ~/.ssh ~/.config/chezmoi ~/.config/systemd/user

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
    echo "Starting dotfiles sync engine..."

    TRACKED="{{ TRACKED_FILE }}"
    TRACKED_ENC="{{ TRACKED_ENC_FILE }}"

    echo "=> Running chezmoi re-add..."
    chezmoi re-add --force

    # reads tracking lists into arrays and separates exclusion patterns
    TRACKED_LIST=()
    EXCLUDE_LIST=()
    if [ -f "$TRACKED" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi
            
            is_exclude=0
            if [[ "$line" == !* ]]; then
                is_exclude=1
                line="${line#!}"
            fi

            if [[ "$line" == /* ]]; then
                expanded="$line"
            elif [[ "$line" == ~* ]]; then
                expanded="${line/#\~/$HOME}"
            else
                expanded="$HOME/$line"
            fi
            
            if [ $is_exclude -eq 1 ]; then
                EXCLUDE_LIST+=("$expanded")
            else
                TRACKED_LIST+=("$expanded")
            fi
        done < "$TRACKED"
    fi

    ENC_LIST=()
    ENC_EXCLUDE_LIST=()
    if [ -f "$TRACKED_ENC" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi

            is_exclude=0
            if [[ "$line" == !* ]]; then
                is_exclude=1
                line="${line#!}"
            fi

            if [[ "$line" == /* ]]; then
                expanded="$line"
            elif [[ "$line" == ~* ]]; then
                expanded="${line/#\~/$HOME}"
            else
                expanded="$HOME/$line"
            fi
            
            if [ $is_exclude -eq 1 ]; then
                ENC_EXCLUDE_LIST+=("$expanded")
            else
                ENC_LIST+=("$expanded")
            fi
        done < "$TRACKED_ENC"
    fi

    echo "=> Discovering and tracking new files..."

    # gathers all files in the home directory that chezmoi is not currently tracking
    mapfile -t unmanaged_files < <(chezmoi unmanaged)

    for rel_path in "${unmanaged_files[@]}"; do
        full_path="$HOME/$rel_path"

        # skips path if it matches any exclusion pattern
        is_ignored=0
        for ex in "${EXCLUDE_LIST[@]}" "${ENC_EXCLUDE_LIST[@]}"; do
            if [[ "$full_path" == "$ex" ]] || [[ "$full_path" == "$ex"/* ]] || [[ "$full_path" =~ $ex ]]; then
                is_ignored=1
                break
            fi
        done
        if [ $is_ignored -eq 1 ]; then continue; fi

        # prioritizes encryption check with regex support
        matched=0
        for prefix in "${ENC_LIST[@]}"; do
            if [[ "$full_path" == "$prefix" ]] || [[ "$full_path" == "$prefix"/* ]] || [[ "$full_path" =~ $prefix ]]; then
                echo "  -> Encrypting & Adding new file: $full_path"
                chezmoi add --encrypt --force "$full_path"
                matched=1
                break
            fi
        done

        if [ $matched -eq 1 ]; then continue; fi

        # falls back to standard tracking check with regex support
        for prefix in "${TRACKED_LIST[@]}"; do
            if [[ "$full_path" == "$prefix" ]] || [[ "$full_path" == "$prefix"/* ]] || [[ "$full_path" =~ $prefix ]]; then
                echo "  -> Adding new file: $full_path"
                chezmoi add --force "$full_path"
                break
            fi
        done
    done

    echo "=> Cleaning up orphaned and untracked files..."

    # builds whitelist of core configurations that must never be untracked
    VALID_PREFIXES=(
        "${TRACKED_LIST[@]}"
        "${ENC_LIST[@]}"
        "$HOME/.config/chezmoi"
        "$HOME/.config/systemd/user/dotfiles-upload.service"
        "$HOME/.config/systemd/user/dotfiles-upload.timer"
    )

    # reads managed files into an array to avoid stdin pipe conflicts with chezmoi forget
    mapfile -t managed_files < <(chezmoi managed)

    for tracked_path in "${managed_files[@]}"; do
        full_path="$HOME/$tracked_path"

        # removes file from source state if missing from home directory
        if [ ! -e "$full_path" ]; then
            echo "  -> Forgetting missing file: $full_path"
            chezmoi forget --force "$full_path" || true
            continue
        fi

        # checks if file matches exclusion patterns
        is_ignored=0
        for ex in "${EXCLUDE_LIST[@]}" "${ENC_EXCLUDE_LIST[@]}"; do
            if [[ "$full_path" == "$ex" ]] || [[ "$full_path" == "$ex"/* ]] || [[ "$full_path" =~ $ex ]]; then
                is_ignored=1
                break
            fi
        done

        is_valid=0
        if [ $is_ignored -eq 0 ]; then
            # checks if file path falls under any whitelist prefix, is a parent directory, or matches regex
            for prefix in "${VALID_PREFIXES[@]}"; do
                if [[ "$full_path" == "$prefix" ]] || [[ "$full_path" == "$prefix"/* ]] || [[ "$prefix" == "$full_path"/* ]] || [[ "$full_path" =~ $prefix ]]; then
                    is_valid=1
                    break
                fi
            done
        fi

        # untracks file if it is not in the whitelist or matches an exclusion
        if [ $is_valid -eq 0 ]; then
            echo "  -> Forgetting untracked file: $full_path"
            chezmoi forget --force "$full_path" || true
        fi
    done

    echo "=> Committing and pushing changes..."

    # checks for uncommitted changes or untracked files and suppresses false error outputs
    has_changes=0
    chezmoi git -- diff --quiet 2>/dev/null || has_changes=1
    chezmoi git -- diff --cached --quiet 2>/dev/null || has_changes=1
    if [ -n "$(chezmoi git -- ls-files --others --exclude-standard)" ]; then
        has_changes=1
    fi

    if [ "$has_changes" -eq 1 ]; then
        echo "  -> Staging changes..."
        chezmoi git -- add .

        has_staged=0
        chezmoi git -- diff --cached --quiet 2>/dev/null || has_staged=1

        if [ "$has_staged" -eq 1 ]; then
            echo "  -> Creating commit..."
            chezmoi git -- commit -m "chore: auto-sync dotfiles"
        else
            echo "  -> No changes staged for commit."
        fi

        echo "  -> Pushing to remote..."
        # uses HEAD to automatically set upstream if it is missing
        chezmoi git -- push -u origin HEAD
    else
        echo "  -> No new changes to commit."
    fi

    echo "Sync engine finished."

# appends paths to standard tracking list and opens neovim
dotfiles-add *targets:
    #!/usr/bin/env bash
    if [ -n "{{ targets }}" ]; then
        for target in {{ targets }}; do
            abs_path=$(realpath "$target")
            # restricts additions to files inside the home directory
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
            # restricts additions to files inside the home directory
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

    # prompts for initial destructive action confirmation with 15s timeout
    echo "Warning: This action will permanently delete all previous commit history."
    if ! read -t 15 -p "Are you sure you want to proceed? [y/N] " CONFIRM1; then
        echo -e "\nPrompt timed out. Operation cancelled."
        exit 0
    fi

    if [[ ! "$CONFIRM1" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi

    # prompts for branch protection confirmation with 15s timeout
    echo ""
    echo "Warning: The force push will fail if your remote branch is protected."
    echo "Please verify branch protection is disabled here:"
    echo "https://gitlab.com/{{ REPO_PATH }}/-/settings/repository#js-protected-branches-settings"
    if ! read -t 15 -p "Have you disabled protection for your current branch? [y/N] " CONFIRM2; then
        echo -e "\nPrompt timed out. Operation cancelled."
        exit 0
    fi

    if [[ ! "$CONFIRM2" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled. Please disable branch protection and try again."
        exit 0
    fi

    echo "Resetting repository history..."

    # gets the current branch name
    BRANCH=$(chezmoi git -- branch --show-current)
    if [ -z "$BRANCH" ]; then
        BRANCH="main"
    fi

    # creates a new detached history state
    chezmoi git -- checkout --orphan temp_branch
    chezmoi git -- add -A
    chezmoi git -- commit -m "chore: reset repository history"

    # replaces the old branch with the new one
    chezmoi git -- branch -D "$BRANCH"
    chezmoi git -- branch -m "$BRANCH"

    # forces the remote to accept the overwritten history
    echo "Force pushing to remote..."
    chezmoi git -- push -f -u origin "$BRANCH"

    # runs aggressive garbage collection to free local space
    echo "Cleaning local garbage..."
    chezmoi git -- reflog expire --expire=now --all
    chezmoi git -- gc --prune=now --aggressive

    echo "History cleaned successfully."