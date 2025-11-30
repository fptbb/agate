export project_root := `git rev-parse --show-toplevel`
export git_branch := ` git branch --show-current`

_default:
    @just --list

generate:
    #!/usr/bin/bash
    echo "Generating Containerfile..."
    bluebuild generate ./recipes/recipe.yml -o Containerfile

validate:
    #!/usr/bin/bash
    echo "Validating Bluebuild..."
    bluebuild validate

prune:
    #!/usr/bin/bash
    echo "Pruning Bluebuild..."
    bluebuild prune

build:
    #!/usr/bin/bash
    echo "Building image..."
    bluebuild build ./recipes/recipe.yml

build-iso:
    #!/usr/bin/bash
    echo "Building image iso..."
    sudo bluebuild generate-iso --iso-name agate.iso recipe recipes/recipe.yml

build-iso-online:
    #!/usr/bin/bash
    echo "Building image iso based on online image..."
    sudo bluebuild generate-iso --iso-name agate.iso image quay.io/fptbb/agate:latest
