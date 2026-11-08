set lazy

# Manage Bitwarden CLI sessions using the system keyring
[group("system")]
agate-bitwarden $action="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Display help
    if [[ -z "$action" || "$action" == "help" ]]; then
        echo "Usage: ujust agate-bitwarden <action>"
        echo ""
        echo "Available actions:"
        echo "  status  - Show vault and stored session status"
        echo "  unlock  - Unlock vault and save session to KWallet"
        echo "  lock    - Lock vault and remove stored session"
        echo "  sync    - Synchronize vault with Bitwarden"
        exit 0
    fi

    # Check dependencies
    for cmd in bw secret-tool; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo "error: '$cmd' is not installed" >&2
            exit 1
        }
    done

    # Retrieve the stored session without exporting it globally
    session="$(secret-tool lookup \
        application bitwarden-cli type session 2>/dev/null || true)"

    case "$action" in
        status)
            if [[ -n "$session" ]]; then
                echo "KWallet session: stored"
                BW_SESSION="$session" bw status
            else
                echo "KWallet session: missing"
                env -u BW_SESSION bw status
            fi
            ;;

        unlock)
            echo "Unlocking Bitwarden..."

            env -u BW_SESSION bw unlock --raw |
                secret-tool store \
                    --label="Bitwarden CLI Session" \
                    application bitwarden-cli type session

            echo "Session saved to KWallet."
            ;;

        lock)
            bw lock

            secret-tool clear \
                application bitwarden-cli type session

            echo "Vault locked and KWallet session cleared."
            ;;

        sync)
            [[ -n "$session" ]] || {
                echo "error: no stored session. Run 'ujust agate-bitwarden unlock'." >&2
                exit 1
            }

            BW_SESSION="$session" bw sync
            ;;

        *)
            echo "error: unknown action '$action'" >&2
            echo "Run 'ujust agate-bitwarden' for help." >&2
            exit 1
            ;;
    esac

# Enable or disable optional background services
[group("system")]
agate-toggle-services $action="" $target="all":
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
        echo "Usage: ujust agate-toggle-services <action> [target]"
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

# Manage Malachite Distrobox containers
[group("system")]
agate-malachite $action="" $image="":
    #!/usr/bin/env bash
    set -euo pipefail

    URL="https://malachite.fpt.icu"
    ACTION="$action"
    IMAGE="$image"

    # Display help
    if [[ -z "$ACTION" || "$ACTION" == "help" ]]; then
        echo "Usage: ujust agate-malachite <action> [image]"
        echo ""
        echo "Available actions:"
        echo "  list    - List available Malachite images"
        echo "  apply   - Assemble containers from remote configurations"
        echo "  update  - Pull latest images and upgrade containers"
        echo "  purge   - Forcefully remove containers"
        echo ""
        echo "If [image] is omitted, actions apply to all available images."
        exit 0
    fi

    # Validate action
    case "$ACTION" in
        list|apply|update|purge) ;;
        *)
            echo "error: unknown action '$ACTION'" >&2
            exit 1
            ;;
    esac

    # Check dependencies
    for cmd in curl jq; do
        command -v "$cmd" >/dev/null || {
            echo "error: missing dependency '$cmd'" >&2
            exit 1
        }
    done

    # Fetch metadata once, only when requested
    JSON="$(curl -fsSL --connect-timeout 10 "$URL/images.json")"

    jq -e '.images | type == "object"' >/dev/null <<< "$JSON" || {
        echo "error: invalid Malachite image metadata" >&2
        exit 1
    }

    # List available images
    if [[ "$ACTION" == "list" ]]; then
        echo "Available Malachite images:"
        echo ""

        jq -r '
            .images
            | to_entries
            | sort_by(.key)[]
            | "  \(.key) - \(.value.title): \(.value.summary)"
        ' <<< "$JSON"

        exit 0
    fi

    # Resolve requested images
    if [[ -n "$IMAGE" ]]; then
        jq -e --arg img "$IMAGE" '.images | has($img)' \
            >/dev/null <<< "$JSON" || {
                echo "error: unknown image '$IMAGE'" >&2
                echo "Run 'ujust agate-malachite list' for available images." >&2
                exit 1
            }

        images=("$IMAGE")
    else
        mapfile -t images < <(jq -r '.images | keys[]' <<< "$JSON")
    fi

    # Check action dependencies
    case "$ACTION" in
        apply|update)
            command -v distrobox >/dev/null || {
                echo "error: distrobox is missing" >&2
                exit 1
            }
            ;;
    esac

    if [[ "$ACTION" == "update" ]]; then
        command -v podman >/dev/null || {
            echo "error: podman is missing" >&2
            exit 1
        }
    fi

    # Execute requested action
    for img in "${images[@]}"; do
        echo "Processing malachite-$img..."

        case "$ACTION" in
            apply)
                assemble="$(jq -er --arg img "$img" \
                    '.images[$img].assemble' <<< "$JSON")"

                distrobox assemble create --replace \
                    --file "$URL/$assemble"
                ;;

            update)
                reference="$(jq -er --arg img "$img" \
                    '.images[$img].reference' <<< "$JSON")"

                podman pull "$reference"
                distrobox upgrade "$img"
                ;;

            purge)
                distrobox rm -f "$img"
                ;;
        esac
    done

    echo "Done."

# Container Cleanup (Podman/Docker)
[group("system")]
agate-container-cleanup $action="":
    #!/usr/bin/bash
    ACTION="$action"

    if [ -z "$ACTION" ]; then
        echo "Usage: ujust agate-container-cleanup <action>"
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

# Manage the system-wide Tor transparent proxy
[group("system")]
agate-toggle-tor $action="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Display help
    if [[ -z "$action" || "$action" == "help" ]]; then
        echo "Usage: ujust agate-toggle-tor <action>"
        echo ""
        echo "Available actions:"
        echo "  enable   - Enable Tor transparent proxy"
        echo "  disable  - Disable Tor and remove firewall rules"
        echo "  toggle   - Switch between enabled and disabled"
        echo "  status   - Show Tor service and proxy status"
        exit 0
    fi

    # Validate action
    case "$action" in
        enable|disable|toggle|status) ;;
        *)
            echo "error: unknown action '$action'" >&2
            exit 1
            ;;
    esac

    for cmd in sudo nft systemctl; do
        command -v "$cmd" >/dev/null || {
            echo "error: missing dependency '$cmd'" >&2
            exit 1
        }
    done

    # Authenticate before making system changes
    sudo -v

    # Check existing nftables tables
    has_ipv4() {
        sudo nft list table ip tor_proxy >/dev/null 2>&1
    }

    has_ipv6() {
        sudo nft list table ip6 tor_proxy_v6 >/dev/null 2>&1
    }

    # Display current state
    show_status() {
        if has_ipv4 && has_ipv6; then
            echo "Tor proxy: enabled"
        elif has_ipv4 || has_ipv6; then
            echo "Tor proxy: partially configured"
        else
            echo "Tor proxy: disabled"
        fi

        echo "Tor service: $(systemctl is-active tor.service 2>/dev/null || true)"
    }

    # Remove firewall rules and stop Tor
    disable_proxy() {
        echo "Disabling Tor transparent proxy..."

        if has_ipv4; then
            sudo nft delete table ip tor_proxy
        fi

        if has_ipv6; then
            sudo nft delete table ip6 tor_proxy_v6
        fi

        sudo systemctl stop tor.service
        echo "Tor proxy disabled."
    }

    # Configure and start transparent proxy
    enable_proxy() {
        if has_ipv4 && has_ipv6; then
            echo "Tor proxy is already enabled."
            sudo systemctl start tor.service
            return
        fi

        if has_ipv4 || has_ipv6; then
            echo "error: incomplete firewall configuration" >&2
            echo "Run 'ujust agate-toggle-tor disable' first." >&2
            exit 1
        fi

        echo "Configuring Tor transparent proxy..."

        # Restore missing service user
        if ! getent passwd toranon >/dev/null; then
            sudo useradd -r -M -U \
                -d /var/lib/tor \
                -s /sbin/nologin toranon
        fi

        # Configure directories and SELinux contexts
        for dir in /var/lib/tor /run/tor /var/log/tor; do
            sudo install -d -o toranon -g toranon -m 700 "$dir"
            sudo chown -R toranon:toranon "$dir"

            if command -v restorecon >/dev/null; then
                sudo restorecon -R "$dir"
            fi
        done

        # Allow Tor to bind to unreserved proxy ports
        if command -v getsebool >/dev/null &&
           getsebool tor_bind_all_unreserved_ports >/dev/null 2>&1; then

            if [[ "$(getsebool tor_bind_all_unreserved_ports | awk '{print $3}')" != "on" ]]; then
                echo "Configuring SELinux boolean..."
                sudo setsebool -P tor_bind_all_unreserved_ports on
            fi
        fi

        # IPv4 redirection and IPv6 leak prevention
        rules="$(printf '%s\n' \
            'table ip tor_proxy {' \
            '    chain nat_output {' \
            '        type nat hook output priority -105; policy accept;' \
            '' \
            '        meta skuid "toranon" accept' \
            '' \
            '        udp dport 53 redirect to :9053' \
            '        tcp dport 53 redirect to :9053' \
            '' \
            '        oifname "lo" accept' \
            '        ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept' \
            '' \
            '        tcp dport != 22 redirect to :9052' \
            '    }' \
            '' \
            '    chain filter_output {' \
            '        type filter hook output priority -5; policy drop;' \
            '' \
            '        meta skuid "toranon" accept' \
            '' \
            '        oifname "lo" accept' \
            '        ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept' \
            '' \
            '        ct state established,related accept' \
            '    }' \
            '}' \
            '' \
            'table ip6 tor_proxy_v6 {' \
            '    chain filter_output {' \
            '        type filter hook output priority -5; policy drop;' \
            '        oifname "lo" accept' \
            '    }' \
            '}')"

        # Verify firewall syntax before activation
        printf '%s\n' "$rules" | sudo nft --check -f -

        # Start Tor before activating redirection
        sudo systemctl start tor.service

        if ! systemctl is-active --quiet tor.service; then
            echo "error: Tor service failed to start" >&2
            exit 1
        fi

        # Apply firewall rules atomically
        printf '%s\n' "$rules" | sudo nft -f -

        echo "Tor proxy enabled."
    }

    # Execute requested action
    case "$action" in
        enable)
            enable_proxy
            ;;
        disable)
            disable_proxy
            ;;
        toggle)
            if has_ipv4 || has_ipv6; then
                disable_proxy
            else
                enable_proxy
            fi
            ;;
        status)
            show_status
            ;;
    esac

# Analyze Btrfs compression and deduplication, using Alpine if needed
[group("system")]
agate-compsize-report $target="/var":
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
