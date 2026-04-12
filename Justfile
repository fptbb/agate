export project_root := `git rev-parse --show-toplevel`
export git_branch := `git branch --show-current`

# configures payload and iso references
username := "fptbb"
image_name := "agate"
image_tag := "latest"
online_image := "quay.io/fptbb/agate:latest"
payload_ref := "localhost/payload:latest"
iso_dest := "agate-live-amd64.iso"

_default:
    @just --list

generate:
    #!/usr/bin/bash
    bluebuild generate ./recipes/recipe.yml -o Containerfile

validate:
    #!/usr/bin/bash
    bluebuild validate

prune:
    #!/usr/bin/bash
    bluebuild prune

build:
    #!/usr/bin/bash
    bluebuild build ./recipes/recipe.yml

build-installer:
    #!/usr/bin/bash
    sudo bluebuild generate-iso --iso-name agate-installer.iso recipe recipes/recipe.yml

build-live-iso: prepare-titanoboa build-payload run-titanoboa clean

prepare-titanoboa:
    #!/usr/bin/env bash
    if [ ! -d "titanoboa" ]; then
        git clone https://github.com/ublue-os/titanoboa.git titanoboa
    else
        git -C titanoboa pull
    fi
    # prevents pulling local images from remote registry
    sed -i '/pull .*image/d' titanoboa/[Jj]ustfile

build-payload:
    #!/usr/bin/env bash
    # requires the local installer directory to exist
    BASE_IMAGE="{{online_image}}"
    INSTALL_IMAGE_PAYLOAD="{{online_image}}"
    FLATPAK_DIR_SHORTNAME="kde_flatpaks"

    # shares host network to prevent curl timeouts
    sudo podman build \
        --network=host \
        --cap-add sys_admin \
        --security-opt label=disable \
        --build-arg BASE_IMAGE="$BASE_IMAGE" \
        --build-arg INSTALL_IMAGE_PAYLOAD="$INSTALL_IMAGE_PAYLOAD" \
        --build-arg FLATPAK_DIR_SHORTNAME="$FLATPAK_DIR_SHORTNAME" \
        -t {{payload_ref}} ./installer/

run-titanoboa:
    #!/usr/bin/env bash
    cd titanoboa
    
    # injects network and privilege flags into podman
    echo '#!/usr/bin/env bash' > podman-wrapper.sh
    echo 'CMD="$1"' >> podman-wrapper.sh
    echo 'shift' >> podman-wrapper.sh
    echo 'if [[ "$CMD" == "run" || "$CMD" == "build" ]]; then' >> podman-wrapper.sh
    echo '    exec /usr/bin/podman "$CMD" --network=host --privileged "$@"' >> podman-wrapper.sh
    echo 'else' >> podman-wrapper.sh
    echo '    exec /usr/bin/podman "$CMD" "$@"' >> podman-wrapper.sh
    echo 'fi' >> podman-wrapper.sh
    chmod +x podman-wrapper.sh

    # sets selinux to permissive for foreign contexts
    SELINUX_STATE=$(getenforce)
    trap 'if [[ "$SELINUX_STATE" == "Enforcing" ]]; then sudo setenforce 1; fi' EXIT
    
    if [[ "$SELINUX_STATE" == "Enforcing" ]]; then
        sudo setenforce 0
    fi

    # bypasses dns timeouts and loop mount limits
    sudo just PODMAN="$(pwd)/podman-wrapper.sh" build {{payload_ref}} 1 /dev/null
    mv ./*.iso ../{{iso_dest}} 2>/dev/null || true

clean:
    #!/usr/bin/env bash
    sudo rm -rf titanoboa/work
    sudo podman rmi {{payload_ref}} -f || true
    sudo podman image prune -f
