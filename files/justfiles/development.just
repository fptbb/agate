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
    #!/usr/bin/bash
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
malachite_json := "/usr/share/agate/malachite.json"

malachite_images := if path_exists(malachite_json) == "true" { `jq -r '.images[].name' /usr/share/agate/malachite.json | xargs` } else { "fedora alpine" }
malachite_repo := if path_exists(malachite_json) == "true" { `jq -r '.repo' /usr/share/agate/malachite.json` } else { "quay.io/fptbb/malachite" }
malachite_link := if path_exists(malachite_json) == "true" { `jq -r '.link' /usr/share/agate/malachite.json` } else { "https://malachite.fpt.icu/" }

# Execute Malachite operations
[group("system")]
malachite action="" image="":
    #!/usr/bin/bash
    ACTION="{{ action }}"
    IMAGES="{{ if image == "" { malachite_images } else { image } }}"

    # prints usage instructions and available commands when executed without arguments
    if [ -z "$ACTION" ]; then
        echo "Usage: ujust malachite <action> [image]"
        echo ""
        echo "Available actions:"
        echo "  apply   - Replaces and assembles containers from remote .ini configurations"
        echo "  update  - Pulls the latest base image and runs distrobox upgrade"
        echo "  purge   - Forcefully removes the containers"
        echo ""
        echo "If [image] is omitted, actions are applied to: $IMAGES"
        exit 0
    fi

    for img in $IMAGES; do
        # routes the requested action to the corresponding distrobox operation
        case $ACTION in
            apply)
                echo "Applying configuration for malachite-$img..."
                distrobox assemble create --replace --file "{{ malachite_link }}$img.ini"
                ;;
            update)
                echo "Updating malachite-$img..."
                podman pull {{ malachite_repo }}:$img
                distrobox upgrade $img
                ;;
            purge)
                echo "Purging malachite-$img..."
                distrobox rm -f $img
                ;;
            *)
                echo "Error: Invalid action '$ACTION'."
                echo "Valid actions are: apply, update, purge"
                exit 1
                ;;
        esac
    done

# Container Cleanup (Podman/Docker)
[group("system")]
container action="":
    #!/usr/bin/bash
    ACTION="{{ action }}"

    if [ -z "$ACTION" ]; then
        echo "Usage: ujust container <action>"
        echo ""
        echo "Available actions:"
        echo "  list  - Lists all containers, images, and volumes"
        echo "  stop  - Stops all running containers"
        echo "  clear - Removes unused containers, networks, images, and volumes"
        echo "  purge - Forcefully stops and removes ALL containers, images, and volumes"
        exit 0
    fi

    # runs operations universally across available container engines
    run_engine() {
        local cmd=$1
        if command -v podman &> /dev/null; then
            echo "[Podman]"
            eval "podman $cmd" || true
        fi
        if command -v docker &> /dev/null; then
            echo "[Docker]"
            eval "docker $cmd" || true
        fi
    }

    case $ACTION in
        list)
            echo "Listing all containers, images, and volumes..."
            run_engine "ps -a"
            run_engine "images"
            run_engine "volume ls"
            ;;
        stop)
            echo "Stopping all running containers..."
            if command -v podman &> /dev/null; then podman stop -a || true; fi
            if command -v docker &> /dev/null; then
                DOCKER_PIDS=$(docker ps -q)
                if [ -n "$DOCKER_PIDS" ]; then docker stop $DOCKER_PIDS || true; fi
            fi
            ;;
        clear)
            echo "Clearing unused resources..."
            run_engine "system prune -f"
            ;;
        purge)
            echo "Purging ALL containers, images, and volumes..."
            if command -v podman &> /dev/null; then
                podman stop -a || true
                podman rm -fa || true
                podman rmi -fa || true
                podman system prune -a -f --volumes || true
            fi
            if command -v docker &> /dev/null; then
                # prevents bash errors if docker queries return empty strings
                DOCKER_ALL=$(docker ps -aq)
                if [ -n "$DOCKER_ALL" ]; then
                    docker stop $DOCKER_ALL || true
                    docker rm -f $DOCKER_ALL || true
                fi

                DOCKER_IMG=$(docker images -aq)
                if [ -n "$DOCKER_IMG" ]; then docker rmi -f $DOCKER_IMG || true; fi

                docker system prune -a -f --volumes || true
            fi
            ;;
        *)
            echo "Error: Invalid action '$ACTION'."
            echo "Valid actions are: list, stop, clear, purge"
            exit 1
            ;;
    esac

toggle-tor:
    #!/usr/bin/bash

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
