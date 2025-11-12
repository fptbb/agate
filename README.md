# <img src="files/system/usr/share/pixmaps/fp-logo.png" alt="Agate Logo" width="45" valign="middle"/> Agate

[![Build Status](https://github.com/fptbb/agate/actions/workflows/build.yml/badge.svg)](https://github.com/fptbb/agate/actions/)

**Website: [os.fpt.icu](https://os.fpt.icu)**

---

## Introduction

Welcome to Agate! This project is a customized, bootable OS image based on [Bazzite](https://bazzite.gg/) (a Fedora KDE variant), built using the [BlueBuild](https://blue-build.org/).

While this is my personal daily driver OS, tailored to my specific workflow and preferences, it's also publicly available as a learning resource or a starting point for your own custom OS image. You can see how certain customizations are made, fork the project to suit your needs, or just draw inspiration for your own builds.

**Disclaimer:** This project includes personal branding and specific configurations that may not be suitable for everyone. It is recommended to review the customizations before use.

## Core Concept

*   **Base Image:** `ghcr.io/ublue-os/bazzite-dx-nvidia:stable`. This provides a solid foundation of Fedora Kinoite (KDE Plasma) with Bazzite's gaming enhancements, developer experience tools, and pre-installed Nvidia drivers.
*   **Immutable & Atomic:** Leveraging `bootc` and `ostree`, the system is reliable, predictable, and robust. Updates are atomic, and you can easily roll back to previous versions.
*   **Customized:** The base image is augmented with personal branding, system tweaks, additional packages, and my preferred set of Flatpaks.
*   **Flatpak-centric:** Most applications are intended to be installed as Flatpaks. The base image modifications are for tools, system-level configurations, and packages that are not suitable for Flatpak.

## Features & Customizations

Here's a summary of what makes Agate unique:

### Branding
*   **Wallpapers:** Custom default desktop and lockscreen wallpapers are included.
*   **MOTD:** A custom "Message of the Day" is shown in the terminal.
*   **OS Info:** The `/usr/lib/os-release` file is updated with Agate branding.

### System-Level Changes & Additions
*   **Google Account Fix:** The KDE Google Account provider is modified to improve Google Drive integration.
*   **Enabled Services:** The following services are enabled by default: `nordvpnd`, `tailscaled`, `netbird`, and `podman.socket`.
*   **Disabled Services:** `NetworkManager-wait-online.service` is disabled to speed up boot times.
*   **Nix Pkgs Manager:** Nix Pkgs are ready to be installed using `just agate-nixpkgs`.

### Included RPM Packages
In addition to the standard Bazzite set, a variety of packages are installed for development (VS Code, Go, buildah), networking (NordVPN, Tailscale, Netbird), system utilities (yadm, kitty, zsh), and many more.

### Default Flatpaks
Comes with a curated selection of default applications including Bitwarden, Spotify, Vesktop (a Discord client), GIMP, Thunderbird, Mission Center, and many more. To be installed on the first start by the system.

## How to Use

You can switch an existing `bootc`-compatible system (like Fedora, Bazzite, or Bluefin) to this image.

**Rebase Command:**
```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/fptbb/agate:latest
```
or
```bash
sudo rpm-ostree rebase ostree-image-signed:docker://quay.io/fptbb/agate:latest
```
After the command completes, reboot your system. You can check the status at any time with `sudo bootc status`.

## Building from Source

If you want to customize this image or build it yourself, you can use the provided `Justfile`.

### Prerequisites
*   A container runtime like [Podman](https://podman.io/).
*   [Just](https://github.com/casey/just), a command runner.

### Build Instructions
1.  **Clone the repository:**
    ```bash
    git clone git@github.com:fptbb/agate.git
    cd fp-os
    ```
2.  **Build the container image:**
    ```bash
    just build
    ```
3.  **(Optional) Build a bootable disk image:**
    You can create an ISO, QCOW2, or other disk image formats.
    ```bash
    # Build an ISO for installation
    just build-iso
    ```
    The generated images will be in the root directory.

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/fptbb/agate
```

## Name Meaning
Many Fedora Atomic Desktops are named after minerals and rocks—often silicates like kinoite or onyx (and even bazzite), evoking the durable, crystalline foundations of these immutable systems. In that spirit, I've named this Bazzite-based image after **Red Fox Agate**, a rare variety of chalcedony quartz whose vibrant orange-red bands, streaked with white, mimic the fur of a red fox.

Sourced exclusively from ancient volcanic geodes in Patagonia, Argentina (notably the Cerro Cristal region near Perito Moreno), Red Fox Agate was first discovered in 1997. Its botryoidal hematite inclusions create that signature "foxy" pattern, with a Mohs hardness of 6.5–7 making it ideal for polished cabochons, jewelry, or display specimens.

For more on this gem: [Red Fox Agate Overview](https://www.geologyin.com/2023/11/red-fox-agate.html)

## Acknowledgements

This project is made possible by the work of the open-source community. Special thanks to:

*   The [Universal Blue](https://universal-blue.org/) project and all its contributors.
*   The [BlueBuild](https://blue-build.org/) project and all its contributors.
*   The creators of the base images and templates.
*   Inspiration from other custom OS projects like [VeneOS](https://github.com/Venefilyn/veneos), [amyos](https://github.com/astrovm/amyos), and [m2os](https://github.com/m2Giles/m2os).

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.
