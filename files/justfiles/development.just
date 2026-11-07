set lazy

# Unlocks Bitwarden CLI session and stores it in the system keyring for secure access
unlock-bitwarden:
    #!/usr/bin/env bash
    set -euo pipefail
    # This depends on user having this on zshrc or bashrc:
    # if command -v secret-tool >/dev/null 2>&1; then export BW_SESSION="$(secret-tool lookup application bitwarden-cli type session)" fi
    # or on fish:
    # if command -v secret-tool >/dev/null 2>&1; then set -x BW_SESSION (secret-tool lookup application bitwarden-cli type session) end
    bw unlock --raw | secret-tool store \
        --label="Bitwarden CLI Session" \
        application bitwarden-cli type session

# Enable or disable optional background services
[group("system")]
toggle-services $action="" $target="all":
    #!/usr/bin/env bash
    set -euo pipefail

    declare -A services=()

    # Load configurations in precedence order
    for file in \
        /usr/share/agate/services.conf \
        /etc/agate/services.conf \
        "${XDG_CONFIG_HOME:-$HOME/.config}/agate/services.conf"; do

        [[ -f "$file" ]] || continue

        while IFS=: read -r name units || [[ -n "$name" ]]; do
            name="${name//[[:space:]]/}"
            [[ -z "$name" || "$name" == \#* ]] && continue

            if [[ -z "${units//[[:space:]]/}" ]]; then
                echo "warning: no units defined for '$name' in $file" >&2
                continue
            fi

            services["$name"]="${units//\$USER/$USER}"
        done < "$file"
    done

    # Show help when called without arguments
    if [[ -z "$action" ]]; then
        echo "Usage: ujust toggle-services <action> [target]"
        echo ""
        echo "Available actions:"
        echo "  enable   - Enable and start services"
        echo "  disable  - Disable and stop services"
        echo ""
        echo "Available targets:"
        echo "  all"

        if ((${#services[@]})); then
            printf '%s\n' "${!services[@]}" | sort | sed 's/^/  /'
        fi

        echo ""
        echo "If [target] is omitted, all configured services are affected."
        exit 0
    fi

    # Validate action
    case "$action" in
        enable|disable) ;;
        *)
            echo "error: invalid action '$action'" >&2
            exit 1
            ;;
    esac

    if ((${#services[@]} == 0)); then
        echo "error: no service mappings found" >&2
        exit 1
    fi

    # Select targets
    if [[ "$target" == "all" ]]; then
        mapfile -t targets < <(printf '%s\n' "${!services[@]}" | sort)
    elif [[ -n "${services[$target]:-}" ]]; then
        targets=("$target")
    else
        echo "error: unknown target '$target'" >&2
        echo "available targets: all, ${!services[*]}" >&2
        exit 1
    fi

    # Apply service state
    for name in "${targets[@]}"; do
        read -r -a units <<< "${services[$name]}"
        echo "$action: $name (${units[*]})"
        sudo systemctl "$action" --now "${units[@]}"
    done

    echo "done."

# Malachite Configuration
malachite_json := "/usr/share/agate/malachite.json"

malachite_images := `curl -fsSL https://malachite.fpt.icu/images.json | jq -r '.images | keys[]' | xargs`
malachite_repo := `curl -fsSL https://malachite.fpt.icu/images.json | jq -r '"\(.registry)/\(.namespace)/\(.image_name)"'`
malachite_link := "https://malachite.fpt.icu/"

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
                assemble=$(curl -fsSL https://malachite.fpt.icu/images.json | jq -r --arg img "$img" '.images[$img].assemble')
                echo "Applying configuration for malachite-$img..."
                distrobox assemble create --replace --file "{{ malachite_link }}$assemble"
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

# Analyze Btrfs compression and deduplication, using Alpine if needed
[group("system")]
compsize-report $target="/var":
    #!/usr/bin/env bash
    set -euo pipefail

    IMAGE="docker.io/library/alpine:3.23"

    # Validate the target and resolve its absolute path
    target="$(realpath -e -- "$target")"

    [[ "$(stat -f -c %T -- "$target")" == "btrfs" ]] || {
        echo "error: target is not on a Btrfs filesystem" >&2
        exit 1
    }

    # Authenticate before performing any work
    echo "Authenticating..."
    sudo -v

    # Create a temporary working directory
    tmp_root="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
    tmp_dir="$(mktemp -d "$tmp_root/agate-compsize.XXXXXXXX")"
    mkdir -p "$tmp_dir/home"

    report="$tmp_dir/report.txt"
    remove_image=false

    # Refresh sudo authentication while running
    (
        while sleep 30; do
            sudo -n -v >/dev/null 2>&1 || break
        done
    ) &
    keepalive_pid=$!

    cleanup() {
        local status=$?
        trap - EXIT

        kill "$keepalive_pid" 2>/dev/null || true
        wait "$keepalive_pid" 2>/dev/null || true

        if [[ "$remove_image" == true ]]; then
            echo "Cleaning up Alpine image..."
            sudo -n podman image rm "$IMAGE" >/dev/null 2>&1 ||
                echo "warning: Alpine image could not be removed" >&2
        fi

        rm -rf -- "$tmp_dir"
        exit "$status"
    }
    trap cleanup EXIT

    echo "Analyzing: $target"

    if command -v compsize >/dev/null 2>&1; then
        # Fast path: use the installed host binary
        echo "Using host compsize..."
        sudo -n compsize -b -x "$target" > "$report"
    else
        # Fallback: run Alpine's compsize inside disposable Distrobox
        echo "Host compsize unavailable; using Alpine..."

        for cmd in distrobox podman; do
            command -v "$cmd" >/dev/null || {
                echo "error: missing fallback dependency '$cmd'" >&2
                exit 1
            }
        done

        if ! sudo -n podman image exists "$IMAGE"; then
            remove_image=true
        fi

        distrobox ephemeral \
            --root \
            --image "$IMAGE" \
            --home "$tmp_dir/home" \
            --volume "$target:/mnt/agate-target:ro" \
            --volume "$tmp_dir:/mnt/agate-results:rw" \
            --additional-flags "--privileged" \
            --pre-init-hooks 'apk add --no-cache btrfs-compsize >/dev/null && /usr/sbin/compsize -b -x /mnt/agate-target > /mnt/agate-results/report.txt' \
            --yes \
            -- true
    fi

    [[ -s "$report" ]] || {
        echo "error: compsize analysis failed or returned no data" >&2
        exit 1
    }

    # Format results from raw byte counts
    awk -v target="$target" '
        /^TOTAL[[:space:]]/ {
            found = 1
            disk = $3
            uncomp = $4
            ref = $5
            gib = 1073741824

            printf "\033[1;34mBtrfs Analysis: %s\033[0m\n", target
            print "---------------------------------------------"
            printf "Logical size:        %.2f GiB\n", ref / gib
            printf "Physical disk usage: %.2f GiB\n", disk / gib
            printf "Total space saved:   \033[1;32m%.2f GiB\033[0m\n", (ref - disk) / gib
            print ""
            printf "Reflinks/dedup:      %.2f GiB\n", (ref - uncomp) / gib
            printf "Compression:         %.2f GiB\n", (uncomp - disk) / gib
            print "---------------------------------------------"
        }

        END {
            if (!found) {
                print "error: no TOTAL result found" > "/dev/stderr"
                exit 1
            }
        }
    ' "$report"