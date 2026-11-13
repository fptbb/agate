export project_root := `git rev-parse --show-toplevel`
export git_branch := `git branch --show-current`

# configures payload and iso references

payload_ref := "localhost/payload:latest"
_default:
    @just --list

generate:
    #!/usr/bin/bash
    bluebuild generate ./recipes/recipe.yml -o Containerfile

validate:
    #!/usr/bin/bash
    bluebuild validate ./recipes/recipe.yml
    bluebuild validate ./recipes/recipe-testing.yml

prune:
    #!/usr/bin/bash
    bluebuild prune

build:
    #!/usr/bin/bash
    bluebuild build ./recipes/recipe.yml

clean:
    #!/usr/bin/env bash
    set -euo pipefail

    sudo rm -rf titanoboa/work
    sudo podman rmi {{ payload_ref }} -f || true
    sudo podman image prune -f

format-justfiles:
    #!/usr/bin/env bash
    set -euo pipefail

    command find ./files/justfiles -type f \( -name '*.just' -o -name 'Justfile' -o -name 'justfile' \) -exec just --unstable --fmt --justfile '{}' \;
    echo "Justfiles formatted."
