# Bazzite DX Port Notes

This image now rebases on `ghcr.io/ublue-os/bazzite-nvidia` and ports over the
useful parts of `bazzite-dx` through `recipes/common-bazzite-port.yml`.

Imported from `bazzite-dx`

- Development packages: `android-tools`, `bcc`, `bpftop`, `bpftrace`,
  `ccache`, `code`, Docker CE tooling, `flatpak-builder`, `git-subtree`,
  `podman-machine`, `podman-tui`, `python3-ramalama`, `restic`, `rclone`,
  `sysprof`, `tiptop`, `usbmuxd`, `waypipe`, and `zsh`.
- Virtualization packages kept for local x86_64 use: `qemu`, `qemu-kvm`,
  `libvirt`, `virt-manager`, `edk2-ovmf`, and `guestfs-tools`.
- Desktop-oriented Bazzite patches: restore `input-remapper` visibility and
  load `iptable_nat` for Docker-compatible workflows.
- Filesystem carry-over: the `/var/opt` to `/usr/lib/opt` relocation from
  `50-fix-opt.sh`.
- First-boot group setup: wheel users are added to `docker`, `libvirt`, and
  `dialout` via `agate-dev-groups.service`.

Intentionally not imported

- `00-image-info.sh`: only adjusts Bazzite DX branding and variant metadata.
- `60-clean-base.sh` and `999-cleanup.sh`: upstream image build cleanup, not a
  good fit for a BlueBuild module.
- `99-build-initramfs.sh`: useful only if you decide to force initramfs
  generation in your own image pipeline.
- ROCm packages: your current image already removes the AMD compute stack.
- Deck/gamemode cleanup from `bazzite-dx`: this image now builds on plain
  `bazzite`, so SteamOS session and autologin undo logic is intentionally
  skipped.
- DX-only helpers around Incus, VFIO, and extra privileged setup hooks.

Interaction with `common-debloat.yml`

- Libvirt units are no longer masked, so the kept virtualization stack can
  actually start.
- `input-remapper.service` is no longer masked, because this port explicitly
  re-enables it.
- Cross-architecture QEMU targets are still removed there, so only the basic
  x86_64 host virtualization stack remains.
