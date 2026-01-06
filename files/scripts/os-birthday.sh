#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

UNIT_PATH="/usr/lib/systemd/system/os-birthday.service"

cat > "$UNIT_PATH" <<'EOF'
[Unit]
Description=Create system installation timestamp
ConditionPathExists=!/var/lib/os-birthday.timestamp

[Service]
Type=oneshot
ExecStart=/usr/bin/env TZ=UTC /usr/bin/date -Is
StandardOutput=append:/var/lib/os-birthday.timestamp

[Install]
WantedBy=multi-user.target
EOF
