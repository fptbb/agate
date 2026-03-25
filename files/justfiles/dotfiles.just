# defines absolute paths dynamically based on the current user environment

HOME_DIR := env_var("HOME")
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

    chezmoi apply

    @printf "[Unit]\nDescription=Sync dotfiles and discover new files\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/ujust dotfiles-re-add\nRuntimeMaxSec=300\nStandardOutput=journal\nStandardError=journal\n" > ~/.config/systemd/user/dotfiles-upload.service
    @printf "[Unit]\nDescription=Run dotfiles sync periodically\n\n[Timer]\nOnBootSec=4h\nOnUnitActiveSec=4h\n\n[Install]\nWantedBy=timers.target\n" > ~/.config/systemd/user/dotfiles-upload.timer

    chmod 644 ~/.config/systemd/user/dotfiles-upload.*
    systemctl --user daemon-reload
    systemctl --user enable --now dotfiles-upload.timer

    @echo "Setup complete. Services created and timer enabled."

# absorbs changes, discovers new files, and cleans up orphans
dotfiles-re-add:
    @echo "Starting dotfiles sync engine..."

    chezmoi re-add

    @if [ -f {{ TRACKED_FILE }} ]; then \
        echo "Reading {{ TRACKED_FILE }}..."; \
        while IFS= read -r line || [ -n "$line" ]; do \
            if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi; \
            if [ -e "$line" ]; then \
                chezmoi add --recursive "$line"; \
            fi; \
        done < {{ TRACKED_FILE }}; \
    fi

    @if [ -f {{ TRACKED_ENC_FILE }} ]; then \
        echo "Reading {{ TRACKED_ENC_FILE }}..."; \
        while IFS= read -r line || [ -n "$line" ]; do \
            if [ -z "$line" ] || [[ "$line" == \#* ]]; then continue; fi; \
            if [ -e "$line" ]; then \
                chezmoi add --encrypt --recursive "$line"; \
            fi; \
        done < {{ TRACKED_ENC_FILE }}; \
    fi

    @echo "Cleaning up orphaned files..."
    @chezmoi managed | while read -r tracked_path; do \
        if [ ! -e "$HOME/$tracked_path" ]; then \
            echo "Removing orphaned file from source: $tracked_path"; \
            chezmoi forget "$HOME/$tracked_path"; \
        fi; \
    done

    @echo "Sync engine finished."

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
    chezmoi add --recursive {{ targets }}

# tracks new sensitive files
dotfiles-add-secret +targets:
    chezmoi add --encrypt --recursive {{ targets }}

# removes files from source state tracking
dotfiles-forget +targets:
    chezmoi forget {{ targets }}

# commits and pushes local changes to gitlab
dotfiles-push message:
    chezmoi git -- add .
    chezmoi git -- commit -m "{{ message }}"
    chezmoi git -- push -u origin main

# shows modified files pending sync
dotfiles-status:
    chezmoi status

# shows line-by-line differences
dotfiles-diff:
    chezmoi diff

# opens file in secure edit mode
dotfiles-edit target:
    chezmoi edit {{ target }}

# tails background sync logs
dotfiles-logs:
    journalctl --user -u dotfiles-upload.service -n 50 -f

# opens tracking lists in default editor
dotfiles-edit-lists:
    ${EDITOR:-nvim} {{ TRACKED_FILE }} {{ TRACKED_ENC_FILE }}
