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

# Malachite Configuration
# Centralized source of truth is at /usr/share/agate/malachite.json

malachite_json := "/usr/share/agate/malachite.json"
malachite_images := if path_exists(malachite_json) == "true" { `jq -r '.images[].name' /usr/share/agate/malachite.json | xargs` } else { "fedora alpine" }
malachite_repo := if path_exists(malachite_json) == "true" { `jq -r '.repo' /usr/share/agate/malachite.json` } else { "quay.io/fptbb/malachite" }

# Create or replace Malachite containers
[group("malachite")]
malachite-setup name="":
    #!/usr/bin/bash
    IMAGES="{{ if name == "" { malachite_images } else { name } }}"
    for img in $IMAGES; do
        echo "Setting up malachite-$img..."
        distrobox create -i {{ malachite_repo }}:$img -n $img --replace -y
    done

# Update Malachite images and containers
[group("malachite")]
malachite-update name="":
    #!/usr/bin/bash
    IMAGES="{{ if name == "" { malachite_images } else { name } }}"
    for img in $IMAGES; do
        echo "Updating malachite-$img..."
        podman pull {{ malachite_repo }}:$img
        distrobox upgrade $img
    done

# Re-create Malachite containers (wiping state)
[group("malachite")]
malachite-recreate name="":
    #!/usr/bin/bash
    IMAGES="{{ if name == "" { malachite_images } else { name } }}"
    for img in $IMAGES; do
        echo "Recreating malachite-$img..."
        distrobox rm -f $img
        distrobox create -i {{ malachite_repo }}:$img -n $img -y
    done

# Remove Malachite containers
[group("malachite")]
malachite-purge name="":
    #!/usr/bin/bash
    IMAGES="{{ if name == "" { malachite_images } else { name } }}"
    for img in $IMAGES; do
        echo "Purging malachite-$img..."
        distrobox rm -f $img
    done

toggle-tor:
    #!/usr/bin/env bash

    # resolves missing user from atomic build process
    if ! getent passwd toranon > /dev/null; then
        sudo useradd -r -M -d /var/lib/tor -s /sbin/nologin toranon
    fi

    # fixes strict unix permissions and selinux contexts required by fedora policy
    for dir in /var/lib/tor /run/tor /var/log/tor; do
        if [ ! -d "$dir" ]; then
            sudo mkdir -p "$dir"
        fi
        sudo chown -R toranon:toranon "$dir"
        sudo chmod 700 "$dir"
        sudo restorecon -R "$dir" 2>/dev/null || true
    done

    # overrides fedora selinux confinement to allow tor to bind to proxy ports >1024
    if command -v getsebool >/dev/null 2>&1; then
        if [ "$(getsebool tor_bind_all_unreserved_ports | awk '{print $3}')" != "on" ]; then
            echo "configuring selinux boolean..."
            sudo setsebool -P tor_bind_all_unreserved_ports 1
        fi
    fi

    if sudo nft list table ip tor_proxy >/dev/null 2>&1; then
        echo "disabling tor transparent proxy..."

        sudo nft delete table ip tor_proxy
        sudo nft delete table ip6 tor_proxy_v6 2>/dev/null || true
        sudo systemctl stop tor.service

        echo "tor proxy disabled."
    else
        echo "enabling tor transparent proxy..."

        sudo systemctl start tor.service

        # injects high-priority tables redirecting to custom ports 9052 and 9053
        sudo nft -f - <<< '
        table ip tor_proxy {
            chain nat_output {
                type nat hook output priority -105; policy accept;

                # allows tor daemon to bypass the proxy
                meta skuid "toranon" accept

                # intercepts all dns before loopback exemption to bypass systemd-resolved
                udp dport 53 redirect to :9053
                tcp dport 53 redirect to :9053

                # exempts loopback and local network subnets from tor routing
                oifname "lo" accept
                ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept

                # redirects all remaining external tcp traffic to tor
                tcp dport != 22 redirect to :9052
            }
            chain filter_output {
                type filter hook output priority -5; policy drop;

                # allows tor daemon outbound connections
                meta skuid "toranon" accept

                # allows local network egress
                oifname "lo" accept
                ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept

                # allows active tcp streams to continue
                ct state established,related accept
            }
        }
        table ip6 tor_proxy_v6 {
            chain filter_output {
                type filter hook output priority -5; policy drop;
                oifname "lo" accept
            }
        }'

        echo "tor proxy active."
    fi
