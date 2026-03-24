# Use absolute paths for background service reliability
HOME_DIR := "/home/fptbb"
TRACKED_FILE := HOME_DIR + "/.bin/tracked"
TRACKED_ENC_FILE := HOME_DIR + "/.bin/tracked_encrypted"

# bootstraps dotfiles from private gitlab repository
dotfiles-setup:
    mkdir -p ~/.ssh ~/.config/chezmoi ~/.config/systemd/user
    @echo "Paste your GitLab SSH private key and press Ctrl+D:"
    @cat > ~/.ssh/dotfiles_key
    chmod 600 ~/.ssh/dotfiles_key
    ssh-keygen -y -f ~/.ssh/dotfiles_key > ~/.ssh/dotfiles_key.pub
    ssh-keyscan gitlab.com >> ~/.ssh/known_hosts

    GIT_SSH_COMMAND="ssh -i ~/.ssh/dotfiles_key -o IdentitiesOnly=yes" chezmoi init git@gitlab.com:fptbb/dotfiles.git

    chezmoi git -- config core.sshCommand "ssh -i ~/.ssh/dotfiles_key -o IdentitiesOnly=yes"
    chezmoi git -- config gpg.format ssh
    chezmoi git -- config user.signingkey ~/.ssh/dotfiles_key.pub
    chezmoi git -- config commit.gpgsign true

    age -d -o ~/.config/chezmoi/key.txt ~/.local/share/chezmoi/age-private-key.enc
    chmod 600 ~/.config/chezmoi/key.txt
    
    # Apply first, then we overwrite the systemd files
    chezmoi apply --non-interactive

    # Re-creates the systemd sync services
    @printf "[Unit]\nDescription=Sync dotfiles and discover new files\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/ujust dotfiles-re-add\nRuntimeMaxSec=300\nStandardOutput=journal\nStandardError=journal\n" > ~/.config/systemd/user/dotfiles-upload.service
    @printf "[Unit]\nDescription=Run dotfiles sync periodically\n\n[Timer]\nOnBootSec=4h\nOnUnitActiveSec=4h\n\n[Install]\nWantedBy=timers.target\n" > ~/.config/systemd/user/dotfiles-upload.timer
    
    chmod 644 ~/.config/systemd/user/dotfiles-upload.*
    systemctl --user daemon-reload
    systemctl --user enable --now dotfiles-upload.timer
    
    @echo "Setup complete. Services created and timer enabled."

# absorbs changes AND discovers new files based on tracking lists
dotfiles-re-add:
    @echo "Starting dotfiles sync engine..."
    # Update existing files
    chezmoi re-add --non-interactive
    
    @# Standard tracking
    @if [ -f {{TRACKED_FILE}} ]; then \
        echo "Reading {{TRACKED_FILE}}..."; \
        while IFS= read -r line || [ -n "$line" ]; do \
            if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi; \
            if [ -e "$line" ]; then \
                echo "Syncing: $line"; \
                chezmoi add --recursive --non-interactive "$line"; \
            fi; \
        done < {{TRACKED_FILE}}; \
    else \
        echo "Warning: {{TRACKED_FILE}} not found."; \
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
    @echo "Sync engine finished."

# Standard maintenance commands
dotfiles-update:
    chezmoi update --non-interactive

dotfiles-apply:
    chezmoi apply --non-interactive

dotfiles-cd:
    chezmoi cd

dotfiles-push message:
    chezmoi git -- add .
    chezmoi git -- commit -m "{{message}}"
    chezmoi git -- push -u origin main