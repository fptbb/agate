# <img src="https://gitlab.com/fpsys/agate/-/raw/assets/system/pixmaps/agate-logo.svg" alt="Agate Logo" width="45" valign="middle"/> Agate

[![Build Status](https://gitlab.com/fpsys/agate/badges/main/pipeline.svg?ignore_skipped=true&key_text=CI%20Pipeline)](https://gitlab.com/fpsys/agate/-/pipelines)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/agate)](https://artifacthub.io/packages/search?repo=agate)

**Website:** [**os.fpt.icu**](https://os.fpt.icu)

## Overview

Agate is a personal, Bazzite-based Fedora Atomic desktop built with [BlueBuild](https://blue-build.org/). It keeps Bazzite's gaming-oriented foundation and KDE Plasma desktop while adding custom branding, system-wide themes, development tools, networking and security utilities, and an optional Niri session.

**Warning:** this image is built for a specific daily-driver setup. The source is shared for reference, but its packages, services, defaults, and security settings may not be appropriate for other systems.

Base image: `ghcr.io/ublue-os/bazzite-nvidia-open` (`latest` for the main image, `testing` for the testing image; KDE Plasma with NVIDIA open drivers).

## What It Does

* Keeps the atomic, image-based Bazzite foundation with transactional updates and rollback support.
* Replaces system branding and supplies Agate icons, wallpapers, installer assets, and KDE defaults. New user profiles default to Catppuccin Mocha Sapphire, Kora icons, Catppuccin cursors, and the Fox1 wallpaper; Frappe/Latte variants and PlasMusic are also included.
* Installs an alternative Niri Wayland session with Dux Shell, Dux Search, and supporting utilities such as Alacritty, cava, matugen, and khal. Niri/Dux configurations are seeded for new and existing users without overwriting their personal files. KDE Plasma remains a separate, native session. Dux Files is currently disabled in the package list.
* Adds Docker, Podman tooling, QEMU/KVM, libvirt, Nix, development utilities, and Malachite/Distrobox integration alongside the applications inherited from Bazzite.
* Installs networking and security tools including NordVPN, Tailscale, NetBird, Portmaster, DNSCrypt Proxy, Tor, VeraCrypt, and WhatPulse's packet-capture service. Tor's transparent proxy is opt-in rather than enabled at boot.
* Enables the configured DNSCrypt, NordVPN, Tailscale, container, development-group, update, and WhatPulse services; NetBird, Portmaster, and Nix have their own setup scripts.
* Adds boot-time security settings, FIDO2 initramfs support, and `ujust` helpers for YubiKey/LUKS, OpenPGP, Bitwarden, Tor, service management, containers, and Spicetify.

## Recipes

| File | Purpose |
|---|---|
| `recipe.yml` | Builds the main `latest` image from Bazzite's `latest` channel. |
| `recipe-testing.yml` | Builds `testing` from Bazzite's `testing` channel, including a KDE/Qt version-lock removal and upgrade step. |
| `common-modules.yml` | Shared module list, system files, and OS identity for both channels. |
| `common.yml` | Kernel arguments, initramfs, and cosign signing. Required, and must stay last. |
| `common-packages.yml` | Additional RPMs and repositories, networking/security scripts, and services. |
| `common-dev.yml` | Development, container, virtualization, and Nix setup, plus development/security `ujust` tasks. |
| `common-dux.yml` | Niri, Dux Shell, Dux Search, supporting packages, and session integration. |
| `common-theming.yml` | System-wide themes, wallpapers, Nerd Fonts, and the Spicetify task. |
| `common-cleanup.yml` | Removes selected unused Plasma/Oxygen and Steam Deck preset packages. |

Both channels share the same core modules and branding process. The testing recipe additionally removes KDE/Qt version locks and upgrades related desktop packages before the shared modules run. `AGATE_CHANNEL` selects the branding for each build.

Changes to recipes take effect only after building a new image and deploying or rebasing to it. System-wide theme assets are fetched during the build from the project's `assets` branch and their upstream repositories.

## Building from Source

Requires [Podman](https://podman.io/), [Just](https://github.com/casey/just), and the [BlueBuild CLI](https://blue-build.org/).

```bash
git clone git@gitlab.com:fpsys/agate.git
cd agate
just build
```

Other build tasks:

| Command | Description |
|---|---|
| `just build` | Build the main image using `recipe.yml`. |
| `just validate` | Validate both BlueBuild recipes. |
| `just generate` | Generate a `Containerfile` from the main recipe for inspection. |
| `just prune` | Remove cached BlueBuild build artifacts. |
| `just format-justfiles` | Format the bundled `files/justfiles/` recipes. |
| `just build-installer` | Generate a bootable installer ISO with BlueBuild. Requires `sudo`. |
| `just build-live-iso` | Build a live ISO through [titanoboa](https://github.com/ublue-os/titanoboa) and a local installer payload. Requires `sudo`. |

The live ISO workflow checks out `titanoboa` automatically, but its payload step also expects a local `installer/` directory, which is not included in this repository. The main and testing images also have separate GitHub Actions builds; GitLab CI builds the main image and publishes repository metadata and pages.

## How to Use

Rebase an existing compatible Fedora Atomic / Bazzite installation to the main image:

```bash
sudo rpm-ostree rebase ostree-unverified-registry:quay.io/fpsys/agate:latest
```

The image is also published to GitHub Container Registry:

```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/fptbb/agate:latest
```

For the experimental channel, replace `latest` with `testing`. Reboot to boot the newly deployed image. Inspect deployments with `rpm-ostree status` or `sudo bootc status` on systems using bootc.

## Helper Tasks

After rebasing, run `ujust --list` to see the available tasks. The Agate-specific commands include:

* `agate-pgp` — manage OpenPGP keys, smartcards, keyservers, encryption, signatures, Git signing, and key backups. Optional configuration: `${XDG_CONFIG_HOME:-$HOME/.config}/agate/pgp.conf`.
* `agate-yubikey` — register FIDO2 keys, configure SDDM or system-wide PAM authentication, and enroll/remove YubiKey-backed LUKS2 unlock methods.
* `agate-bitwarden` — manage Bitwarden CLI unlock sessions through the system secret service/KWallet (`status`, `unlock`, `lock`, and `sync`). Requires the Bitwarden CLI and `secret-tool`.
* `agate-toggle-services` — enable or disable groups of optional services. Defaults are in `/usr/share/agate/services.conf`, with overrides in `/etc/agate/services.conf` and `${XDG_CONFIG_HOME:-$HOME/.config}/agate/services.conf`.
* `agate-toggle-tor` — enable, disable, toggle, or inspect a system-wide Tor transparent proxy using nftables.
* `agate-malachite` — apply, update, or purge Malachite-managed Distrobox containers.
* `agate-container-cleanup` — list, stop, clean, or purge Podman and Docker resources.
* `agate-compsize-report` — inspect Btrfs compression and deduplication for a selected path.
* `agate-spicetify` — configure Spicetify for Spotify Flatpak and install its Marketplace.

Several helpers are interactive or modify system authentication, firewall rules, disk encryption, or container state. Review their help output before using them. Chezmoi and `fp-dotfiles-manager` are installed as tools, but Agate no longer ships its former dotfiles-specific `ujust` tasks.

## Verification

Images are signed with [cosign](https://github.com/sigstore/cosign). The public key is published at [`https://os.fpt.icu/cosign.pub`](https://os.fpt.icu/cosign.pub) and in this repository as [`cosign.pub`](cosign.pub).

```bash
cosign verify --key http://os.fpt.icu/cosign.pub quay.io/fpsys/agate:latest
```

The shared kernel arguments include `lockdown=integrity` and `sysctl.kernel.kexec_load_disabled=1`; confirm compatibility with your own hardware and workflows before deploying.

## Name Meaning

Many Fedora Atomic Desktops are named after minerals and rocks—often silicates like kinoite or onyx (and even bazzite), evoking the durable, crystalline foundations of these immutable systems. In that spirit, I've named this Bazzite-based image after **Red Fox Agate**, a rare variety of chalcedony quartz whose vibrant orange-red bands, streaked with white, mimic the fur of a red fox.

Sourced exclusively from ancient volcanic geodes in Patagonia, Argentina (notably the Cerro Cristal region near Perito Moreno), Red Fox Agate was first discovered in 1997. Its botryoidal hematite inclusions create that signature "foxy" pattern, with a Mohs hardness of 6.5–7 making it ideal for polished cabochons, jewelry, or display specimens.

For more on this gem: [Red Fox Agate Overview](https://www.geologyin.com/2023/11/red-fox-agate.html)

## Acknowledgements

This project is made possible by the work of the open-source community. Special thanks to:

* The [Universal Blue](https://universal-blue.org/) project and all its contributors.
* The [BlueBuild](https://blue-build.org/) project and all its contributors.
* Inspiration from other custom OS projects like [VeneOS](https://github.com/Venefilyn/veneos), [amyos](https://github.com/astrovm/amyos), and [m2os](https://github.com/m2Giles/m2os).
* And **this community**:
  ![Billions Must KDE](https://gitlab.com/fpsys/agate/-/raw/assets/bmk.png)

## License

Licensed under the Mozilla Public License 2.0. See [LICENSE](LICENSE).
