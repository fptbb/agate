# bootstraps dotfiles from private gitlab repository
dotfiles-setup:
    #!/usr/bin/bash
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

    @printf "[Unit]\nDescription=Absorb local changes into chezmoi\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/chezmoi re-add\n" > ~/.config/systemd/user/chezmoi-re-add.service
    @printf "[Unit]\nDescription=Run chezmoi re-add periodically\n\n[Timer]\nOnBootSec=4h\nOnUnitActiveSec=4h\n\n[Install]\nWantedBy=timers.target\n" > ~/.config/systemd/user/chezmoi-re-add.timer

    @echo ""
    @echo "WARNING: The auto-sync service has been created but not enabled."
    @echo "To enable it, run: systemctl --user enable --now chezmoi-re-add.timer"

# fetches updates from gitlab and applies them
dotfiles-update:
    chezmoi update

# applies pending local changes to the system
dotfiles-apply:
    chezmoi apply

# opens a shell inside the dotfiles source directory
dotfiles-cd:
    chezmoi cd

# tracks a new file or folder
dotfiles-add target:
    chezmoi add {{target}}

# tracks a new sensitive file with age encryption
dotfiles-add-secret target:
    chezmoi add --encrypt {{target}}

# absorbs changes made directly to tracked files in the home directory
dotfiles-re-add:
    chezmoi re-add

# commits and pushes local changes to gitlab
dotfiles-push message:
    chezmoi git -- add .
    chezmoi git -- commit -m "{{message}}"
    chezmoi git -- push -u origin main