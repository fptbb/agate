#!/usr/bin/env bash
set ${SET_X:+-x} -eou pipefail
trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG
log() { echo "=== $* ==="; }

repo_id="copr:copr.fedorainfracloud.org:group_kdesig:kde-final"

# Ensure the COPR is enabled.
if ! dnf5 repolist --enabled | grep -Fq "$repo_id"; then
    log "ERROR: KDE Final COPR is not enabled: $repo_id" >&2
    exit 1
fi

# Query package names, explicitly separating each result with a newline.
if ! available_names="$(
    dnf5 repoquery --available \
        --repo="$repo_id" \
        --queryformat='%{name}\n'
)"; then
    log "ERROR: Failed to query KDE Final COPR." >&2
    exit 1
fi

# Match COPR package names against currently installed packages.
mapfile -t packages < <(
    comm -12 \
        <(rpm -qa --qf '%{NAME}\n' | LC_ALL=C sort -u) \
        <(printf '%s\n' "$available_names" | LC_ALL=C sort -u)
)

if ((${#packages[@]} == 0)); then
    log "ERROR: No installed packages matched the COPR. Aborting." >&2
    exit 1
fi

printf 'Synchronizing %d installed packages:\n' "${#packages[@]}"
printf '  %s\n' "${packages[@]}"

# Synchronize matching packages and resolve dependencies.
dnf5 distro-sync --refresh --allowerasing --assumeyes \
    "${packages[@]}"

log "KDE Final package synchronization completed."
