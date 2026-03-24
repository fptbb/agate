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

    chezmoi git -- config core.sshCommand "ssh -i ~/.ssh/dotfiles_key -o IdentitiesOnly=yes"
    chezmoi git -- config gpg.format ssh
    chezmoi git -- config user.signingkey ~/.ssh/dotfiles_key.pub
    chezmoi git -- config commit.gpgsign true

    age -d -o ~/.config/chezmoi/key.txt ~/.local/share/chezmoi/age-private-key.enc
    chmod 600 ~/.config/chezmoi/key.txt
    chezmoi apply

    @printf "[Unit]\nDescription=Sync dotfiles and discover new files\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/just -f %h/justfile dotfiles-re-add\n" > ~/.config/systemd/user/chezmoi-re-add.service
    @printf "[Unit]\nDescription=Run dotfiles sync periodically\n\n[Timer]\nOnBootSec=4h\nOnUnitActiveSec=4h\n\n[Install]\nWantedBy=timers.target\n" > ~/.config/systemd/user/chezmoi-re-add.timer

    @echo ""
    @echo "WARNING: Enable the service: systemctl --user enable --now chezmoi-re-add.timer"

# fetches updates from gitlab and applies them
dotfiles-update:
    chezmoi update

# applies pending local changes to the system
dotfiles-apply:
    chezmoi apply

# opens a shell inside the dotfiles source directory
dotfiles-cd:
    chezmoi cd

# tracks new files or folders
dotfiles-add +targets:
    chezmoi add --recursive {{targets}}

# tracks new sensitive files
dotfiles-add-secret +targets:
    chezmoi add --encrypt --recursive {{targets}}

# absorbs changes AND discovers new files based on both tracked files
dotfiles-re-add:
    chezmoi re-add
    @# Standard tracking
    @if [ -f {{TRACKED_FILE}} ]; then \
        while IFS= read -r line || [ -n "$line" ]; do \
            if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi; \
            if [ -e "$line" ]; then \
                echo "Syncing standard: $line"; \
                chezmoi add --recursive "$line"; \
            fi; \
        done < {{TRACKED_FILE}}; \
    fi
    @# Encrypted tracking
    @if [ -f {{TRACKED_ENC_FILE}} ]; then \
        while IFS= read -r line || [ -n "$line" ]; do \
            if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi; \
            if [ -e "$line" ]; then \
                echo "Syncing encrypted: $line"; \
                chezmoi add --encrypt --recursive "$line"; \
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