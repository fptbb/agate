# <img src="files/system/usr/share/pixmaps/fp-logo.png" alt="Agate Logo" width="45" valign="middle"/> Agate

[![Build Status](https://gitlab.com/fpsys/agate/badges/main/pipeline.svg?ignore_skipped=true&key_text=CI%20Pipeline)](https://gitlab.com/fpsys/agate/-/pipelines)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/agate)](https://artifacthub.io/packages/search?repo=agate)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/agate-alt)](https://artifacthub.io/packages/search?repo=agate-alt)

**Website: [os.fpt.icu](https://os.fpt.icu)**

---

## Introduction

Welcome to Agate! This project is a customized, bootable OS image based on [Bazzite](https://bazzite.gg/) (a Fedora KDE variant), built using [BlueBuild](https://blue-build.org/).

While this is my personal daily driver OS, tailored to my specific workflow and preferences, it is publicly available as a learning resource or a starting point for your own custom OS. You can see how specific customizations are layered onto Bazzite, fork the project to suit your needs, or draw inspiration for your own immutable builds.

**Disclaimer:** This project includes personal branding and specific configurations that may not be suitable for everyone. Review the customizations carefully before adopting.

## Core Concept

*   **Base Image:** `ghcr.io/ublue-os/bazzite-dx-nvidia:latest`. This provides a solid foundation of Fedora Kinoite (KDE Plasma) with Bazzite's gaming enhancements, developer tools, and pre-installed Nvidia drivers.
*   **Immutable & Atomic:** Leveraging `bootc` and `ostree`, the system is reliable, predictable, and robust. Updates are atomic, and you can easily roll back to previous states.
*   **Customized Layering:** The base image is augmented with personal branding, additional development packages, custom copr repos, and an expansive set of pre-installed Flatpaks.
*   **Flatpak-Centric:** Most user-facing applications are installed as Flatpaks at build-time.

## Features & Customizations

### System-Level Changes & Additions
*   **Google Account Fix:** The KDE Google Account provider is modified to improve Google Drive integration.
*   **Enabled Services:** The following services are enabled by default: `nordvpnd`, `tailscaled`, `netbird`, and `podman.socket`.
*   **Disabled Services:** `NetworkManager-wait-online.service` is disabled to speed up boot times.
*   **Nix Pkgs Manager:** Nix Pkgs are ready to be installed using `just agate-nixpkgs`.
*   **Enabled Services:** Hardened networking and tracking via `whatpulse`, and `opensnitch` application firewall natively enabled out of the box.
*   **Copr Repositories:** Leverages external coprs for tools like `yadm`, `VeraCrypt`, and `linuxtoys`.

### Included RPM Packages
In addition to the standard Bazzite offering, Agate directly layers on heavy development, packaging, and debugging tools, for things like development, networking (mostly dependencies for opensnitch and whatpulse), utilities, and integrations.

### Pre-Installed System Flatpaks
Agate ships with a curated selection of default applications installed directly to the system space, including:
*   **Web & Comm:** Zen Browser (`app.zen_browser.zen`), Thunderbird, Discord/Vesktop alternative clients.
*   **Gaming:** Ryujinx, PrismLauncher, MCPE Launcher, Sober, Vinegar, Heroic Games Launcher, Bottles.
*   **Development & Setup:** Podman Desktop, QtCreator, Insomnia, Gitnuro, Obsidian.
*   **Media & Production:** OBS Studio, GIMP, Audacity, Spotify.

## How to Use

You can switch an existing `bootc`-compatible system to this custom image.

**Rebase Command:**
```bash
sudo rpm-ostree rebase ostree-image-signed:docker://quay.io/fptbb/agate:latest
```
or, as an alternative mirror, use Github
```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/fptbb/agate:latest
```
After the command completes, reboot your system. You can check the status at any time with `sudo bootc status`.

## Building from Source

To customize this image or build it yourself locally, you can use the provided `Justfile`.

### Prerequisites
*   A container runtime like [Podman](https://podman.io/).
*   [Just](https://github.com/casey/just), a command runner.

### Build Instructions
1.  **Clone the repository:**
    ```bash
    git clone git@github.com:fptbb/agate.git
    cd agate
    ```
2.  **Build the container image:**
    ```bash
    just build
    ```
3.  **(Optional) Build a bootable disk image:**
    You can create an ISO, QCOW2, or other disk image formats.
    ```bash
    just build-iso
    ```
    The generated images will be in the root directory.

## Verification
These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running:

```bash
cosign verify --key https://os.fpt.icu/cosign.pub quay.io/fptbb/agate
```

## Name Meaning
Many Fedora Atomic Desktops are named after minerals and rocks—often silicates like kinoite or onyx (and even bazzite), evoking the durable, crystalline foundations of these immutable systems. In that spirit, I've named this Bazzite-based image after **Red Fox Agate**, a rare variety of chalcedony quartz whose vibrant orange-red bands, streaked with white, mimic the fur of a red fox.

Sourced exclusively from ancient volcanic geodes in Patagonia, Argentina (notably the Cerro Cristal region near Perito Moreno), Red Fox Agate was first discovered in 1997. Its botryoidal hematite inclusions create that signature "foxy" pattern, with a Mohs hardness of 6.5–7 making it ideal for polished cabochons, jewelry, or display specimens.

For more on this gem: [Red Fox Agate Overview](https://www.geologyin.com/2023/11/red-fox-agate.html)

## Acknowledgements

This project is made possible by the work of the open-source community. Special thanks to:

*   The [Universal Blue](https://universal-blue.org/) project and all its contributors.
*   The [BlueBuild](https://blue-build.org/) project and all its contributors.
*   Inspiration from other custom OS projects like [VeneOS](https://github.com/Venefilyn/veneos), [amyos](https://github.com/astrovm/amyos), and [m2os](https://github.com/m2Giles/m2os).

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.
