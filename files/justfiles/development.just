# Install Nix Package Manager
[group("system")]
agate-nixpkgs:
    #!/usr/bin/bash
    /nix/nix-installer

# Install DevBox
[group("system")]
agate-devbox:
    #!/usr/bin/bash
    curl -fsSL https://get.jetify.com/devbox | bash

# toggles specific background services mapped in ~/bin/sys/services.conf
[group("system")]
toggle-services action target="all":
    #!/usr/bin/env bash
    set -euo pipefail
    CONFIG_FILE="$HOME/.bin/sys/services.conf"
    declare -A SERVICES
    # safely exits if the configuration file is missing
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "error: configuration file not found at $CONFIG_FILE"
        echo "please create it using the format: 'name: unit1.service unit2.socket'"
        exit 1
    fi
    # parses the configuration file line by line
    while IFS=':' read -r key val; do
        # trims leading and trailing whitespace
        key=$(echo "$key" | xargs)
        val=$(echo "$val" | xargs)

        # skips empty lines and comments
        [[ -z "$key" || "$key" == \#* ]] && continue

        # handles formatting errors gracefully
        if [[ -z "$val" ]]; then
            echo "warning: skipping malformed line (missing services for '$key')"
            continue
        fi

        # expands the $USER variable for templated services like hhd
        val="${val//\$USER/$USER}"

        SERVICES["$key"]="$val"
    done < "$CONFIG_FILE"
    # ensures there is at least one valid service mapped before proceeding
    if [[ ${#SERVICES[@]} -eq 0 ]]; then
        echo "error: no valid service mappings found in $CONFIG_FILE"
        exit 1
    fi
    ACTION="{{ action }}"
    TARGET="{{ target }}"
    # validates the requested action
    if [[ "$ACTION" != "enable" && "$ACTION" != "disable" ]]; then
        echo "error: action must be 'enable' or 'disable'."
        echo "usage: just toggle-services <enable|disable> [all|TARGET]"
        exit 1
    fi
    # applies the systemctl state
    toggle_units() {
        local units=$1
        if [[ "$ACTION" == "enable" ]]; then
            sudo systemctl enable --now $units
        else
            sudo systemctl disable --now $units
        fi
    }
    # processes targets
    if [[ "$TARGET" == "all" ]]; then
        echo "applying '$ACTION' to all optional services..."
        for key in "${!SERVICES[@]}"; do
            toggle_units "${SERVICES[$key]}"
        done
    elif [[ -n "${SERVICES[$TARGET]:-}" ]]; then
        echo "applying '$ACTION' to $TARGET services..."
        toggle_units "${SERVICES[$TARGET]}"
    else
        echo "error: unknown target '$TARGET'."
        echo "available targets: all, ${!SERVICES[@]}"
        exit 1
    fi

    echo "done."
