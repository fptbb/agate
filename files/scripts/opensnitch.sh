#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

log "Fetching and installing OpenSnitch."

# retrieves the browser_download_url for a github release asset matching a regex
get_github_asset_url() {
    local repo="$1"
    local pattern="$2"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local download_url

    download_url=$(curl -sL "${api_url}" | \
        jq -r --arg regex "${pattern}" \
        '.assets[] | select(.name | test($regex)) | .browser_download_url' | head -n 1)

    if [[ -z "${download_url}" || "${download_url}" == "null" ]]; then
        echo "Error: No asset found matching '${pattern}' in '${repo}'" >&2
        return 1
    fi

    echo "${download_url}"
}

# fetches the daemon
DAEMON_URL=$(get_github_asset_url "evilsocket/opensnitch" "^opensnitch-[0-9].*\.x86_64\.rpm$") || exit 1

# fetches the ui
UI_URL=$(get_github_asset_url "evilsocket/opensnitch" "^opensnitch-ui-.*\.noarch\.rpm$") || exit 1

echo "Installing OpenSnitch... $DAEMON_URL $UI_URL"
# installs directly from url to avoid temp files

# installs the daemon using rpm directly to skip the %post script
# the %post script attempts to restart systemd services, which fails in container builds
rpm -Uvh --nopost "${DAEMON_URL}"

dnf5 install -y "${UI_URL}"