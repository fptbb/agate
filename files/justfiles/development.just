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
