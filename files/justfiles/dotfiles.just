# Paths to the tracking configuration files
TRACKED_FILE := "/home/fptbb/.bin/tracked"
TRACKED_ENC_FILE := "/home/fptbb/.bin/tracked_encrypted"

# bootstraps dotfiles from private gitlab repository
dotfiles-setup:
    mkdir -p ~/.ssh ~/.config/chezmoi ~/.config/systemd/user
    @echo "Paste your GitLab SSH private key and press Ctrl+D:"
    @cat > ~/.ssh/dotfiles_key
    chmod 600 ~/.ssh/dotfiles_key
    ssh-keygen -y -f ~/.ssh/dotfiles_key > ~/.ssh/dotfiles_key.pub
    ssh-keyscan gitlab.com >> ~/.ssh/known_hosts

    GIT_SSH_COMMAND="ssh -i ~/.ssh/dotfiles_key -o IdentitiesOnly=yes" chezmoi init git@gitlab.com:fptbb/dotfiles.git

    # isolates git repository config
    chezmoi git -- config core.sshCommand "ssh -i ~/.ssh/dotfiles_key -o IdentitiesOnly=yes"
    chezmoi git -- config gpg.format ssh
    chezmoi git -- config user.signingkey ~/.ssh/dotfiles_key.pub
    chezmoi git -- config commit.gpgsign true

    # decrypts the repository key
    age -d -o ~/.config/chezmoi/key.txt ~/.local/share/chezmoi/age-private-key.enc
    chmod 600 ~/.config/chezmoi/key.txt
    
    chezmoi apply

    # Re-creates the systemd sync services using ujust
    # Added TimeoutStartSec and RuntimeMaxSec to prevent hanging services
    @printf "[Unit]\nDescription=Sync dotfiles and discover new files\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/ujust dotfiles-re-add\nRuntimeMaxSec=300\nTimeoutStartSec=300\n" > ~/.config/systemd/user/chezmoi-re-add.service
    @printf "[Unit]\nDescription=Run dotfiles sync periodically\n\n[Timer]\nOnBootSec=4h\nOnUnitActiveSec=4h\n\n[Install]\nWantedBy=timers.target\n" > ~/.config/systemd/user/chezmoi-re-add.timer
    
    # Permissions and SELinux fix for Atomic Fedora
    chmod 644 ~/.config/systemd/user/chezmoi-re-add.*
    -restorecon -v ~/.config/systemd/user/chezmoi-re-add.*
    
    systemctl --user daemon-reload
    
    @echo ""
    @echo "Setup complete. To enable the background sync, run:"
    @echo "systemctl --user enable --now chezmoi-re-add.timer"

# fetches updates from gitlab and applies them
dotfiles-update:
    chezmoi update --non-interactive

# applies pending local changes to the system
dotfiles-apply:
    chezmoi apply --non-interactive

# opens a shell inside the dotfiles source directory
dotfiles-cd:
    chezmoi cd

# tracks new files or folders
dotfiles-add +targets:
    chezmoi add --recursive {{targets}}

# tracks new sensitive files
dotfiles-add-secret +targets:
    chezmoi add --encrypt --recursive {{targets}}

# absorbs changes AND discovers new files based on tracking lists
dotfiles-re-add:
    # Run with --non-interactive to prevent hanging on background prompts
    chezmoi re-add --non-interactive
    echo "Re-adding tracked files from configuration lists..."
    @# Standard tracking
    @if [ -f {{TRACKED_FILE}} ]; then \
        while IFS= read -r line || [ -n "$line" ]; do \
            if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi; \
            if [ -e "$line" ]; then \
                echo "Syncing standard: $line"; \
                chezmoi add --recursive --non-interactive "$line"; \
            fi; \
        done < {{TRACKED_FILE}}; \
    fi
    @# Encrypted tracking
    @if [ -f {{TRACKED_ENC_FILE}} ]; then \
        while IFS= read -r line || [ -n "$line" ]; do \
            if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi; \
            if [ -e "$line" ]; then \
                echo "Syncing encrypted: $line"; \
                chezmoi add --encrypt --recursive --non-interactive "$line"; \
            fi; \
        done < {{TRACKED_ENC_FILE}}; \
    fi

# commits and pushes local changes to gitlab
dotfiles-push message:
    chezmoi git -- add .
    chezmoi git -- commit -m "{{message}}"
    chezmoi git -- push -u origin main

# formats this justfile
dotfiles-fmt:
    just --fmt