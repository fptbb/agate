#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

log "Creating /nix and downloading determinite Nix installer."

mkdir -p /nix && \
	curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix -o /nix/determinate-nix-installer.sh && \
	chmod a+rx /nix/determinate-nix-installer.sh

log "Hiding nix and git users from sddm."

FILE="/etc/sddm.conf.d/kde_settings.conf"

# Create file if it doesn't exist
touch "$FILE"
[[ $(tail -c1 "$FILE" | wc -l) -eq 0 ]] || echo >> "$FILE"

# If there is no Users
if ! grep -q '^\[Users\]' "$FILE"; then
    tee -a "$FILE" > /dev/null <<EOF

[Users]
HideUsers=git,nix
EOF
    echo "[Users] section added with HideUsers=git,nix"
    exit 0
fi

# Users exist
awk '
  # when we enter [Users]
  /^\[Users\]/ { in_section = 1; print; next }

  # when another section starts, leave [Users]
  /^\[/ && in_section { in_section = 0 }

  # inside [Users]: if we find HideUsers=, add git and nix if missing
  in_section && /^HideUsers=/ {
    split($0, a, "=")
    gsub(/[, ]+/, ",", a[2])           # normalize commas/spaces
    gsub(/^,|,$/, "", a[2])            # remove leading/trailing commas
    users = (a[2] ? a[2] : "")
    if (users == "") users = "git,nix"
    else {
      if (index("," users ",",",git,") == 0) users = users ",git"
      if (index("," users ",",",nix,") == 0) users = users ",nix"
      gsub(/,+/, ",", users)           # collapse multiple commas
      gsub(/^,|,$/, "", users)         # trim again
    }
    print "HideUsers=" users
    found = 1
    next
  }

  # inside [Users]: any other line => just print
  in_section { print; next }

  # outside [Users] => print unchanged
  { print }

  # after entire file: if we were in [Users] but never saw HideUsers=, add it
  END {
    if (in_section && !found) {
      print "HideUsers=git,nix"
    }
  }
' "$FILE" > "${FILE}.tmp" && mv "${FILE}.tmp" "$FILE"
