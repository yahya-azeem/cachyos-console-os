# CachyOS Console OS — Limine + Pegasus Frontend ISO

A console-first, gamepad-driven live gaming operating system built on top of **CachyOS**.

This ISO replaces the standard desktop environment with the **Pegasus Frontend** game launcher running on the **Cage Wayland Kiosk Compositor**. It is optimized for use with **Sony DualSense (PS5)** controllers out of the box, allowing you to boot straight into a game-console-like experience without a keyboard or mouse.

It also utilizes the **Limine Bootloader** instead of GRUB for maximum compatibility on modern UEFI systems (including MSI motherboards).

## Features

- **Limine Bootloader**: Clean, fast, modern bootloader (replaces GRUB).
- **Console Kiosk Mode**: Boots directly into the Pegasus game launcher on TTY1 auto-login (powered by `cage` Wayland compositor).
- **PlayStation 5 Inspired Theme**: Configured with the beautiful [ProsperoOS theme](https://github.com/PlayingKarrde/prosperoOS).
- **DualSense Support**: In-kernel `hid-playstation` driver and custom udev rules for USB and Bluetooth auto-connection.
- **GitHub Actions CI**: Automated build system that builds, checks, and publishes the ISO directly to GitHub Releases.

## Boot Flow

```
BIOS/UEFI → Limine Bootloader → Kernel (linux-cachyos) → systemd
  → Auto-login (getty tty1) → Cage (Wayland Kiosk)
    → Pegasus Frontend (ProsperoOS Theme, Fullscreen, Gamepad control)
```

## How to Get the ISO

The ISO is built automatically using GitHub Actions:

1. Go to the **Releases** page of this repository.
2. Download the latest `.iso` file.
3. Write it to a USB drive:
   ```bash
   sudo dd if=cachyos-console-os-linux-YYMMDD-limine.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```
4. Boot it on your machine (ensure **Secure Boot is disabled** in BIOS).
