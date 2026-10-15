#!/usr/bin/env bash
set ${SET_X:+-x} -eou pipefail
trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG
log() { echo "=== $* ==="; }

# Find the enabled COPR repository ID.
repo_id="$(
    dnf5 repolist --enabled |
        awk '$1 ~ /kde-final/ { print $1; exit }'
)"

if [[ -z "$repo_id" ]]; then
    log "ERROR: KDE Final COPR repository not found."
    exit 1
fi

# Get installed package names that are also available in this COPR.
mapfile -t packages < <(
    comm -12 \
        <(rpm -qa --qf '%{NAME}\n' | sort -u) \
        <(dnf5 repoquery --available --repoid="$repo_id" --qf '%{name}' | sort -u)
)

if ((${#packages[@]} == 0)); then
    log "No installed packages found in $repo_id; nothing to synchronize."
    exit 0
fi

printf 'Synchronizing %d installed packages from %s\n' \
    "${#packages[@]}" "$repo_id"

# Allow dependency resolution to remove incompatible packages if necessary.
dnf5 distro-sync --refresh --allowerasing --assumeyes \
    "${packages[@]}"
