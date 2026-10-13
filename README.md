<img src="assets/icon.png" width="128" height="128" alt="OpenDisplay icon">

# OpenDisplay

A free macOS menu bar app to control your displays. It looks and works like the system Sound and Wi-Fi menus.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/menu-expanded-dark.png">
    <img src="assets/screenshots/menu-expanded-light.png" width="380" alt="The OpenDisplay menu with all controls of an external display">
  </picture>
</p>

## Features

- **Brightness** for the built-in display and for external displays (over DDC/CI). All sliders follow the macOS brightness curve, so the displays match.
- **Darker than the minimum:** below the lowest backlight level of an external display, the image gets darker in software, down to black.
- **Sync** an external display with the built-in display, so the brightness keys and automatic brightness also change it.
- **Brightness and volume keys** for external displays, with an on-screen indicator.
- **Turn displays on and off** without unplugging them.
- **Volume and mute** for the speakers of external displays.
- **Contrast, input, and color preset** of external displays.
- **Resolution, refresh rate, rotation, and main display.**
- **Extra brightness** for XDR displays: up to 2× the normal maximum.
- **Presets:** save a setup of displays and apply it with one click.

## Screenshots

Each display shows only brightness and volume. Click a display to show all its controls. Presets and settings are in a separate window.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/menu-dark.png">
    <img src="assets/screenshots/menu-light.png" width="380" alt="The short OpenDisplay menu with brightness and volume">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/settings-dark.png">
    <img src="assets/screenshots/settings-light.png" width="460" alt="The OpenDisplay Settings window with keys, Launch at Login, and presets">
  </picture>
</p>

## Requirements

- A Mac with Apple silicon (DDC/CI uses the Apple silicon display interface).
- macOS 14 or later. Some parts need a later version.
- External displays that support DDC/CI for hardware brightness, volume, and input. Other displays get software brightness only.

## Install

1. Download `OpenDisplay-VERSION.zip` from the [latest release](https://github.com/m9tdev/OpenDisplay/releases/latest).
2. Open the zip, and move `OpenDisplay.app` to your Applications folder.
3. Open OpenDisplay. macOS shows a warning, because the app is not notarized by Apple. Click **Done**.
4. In System Settings → Privacy & Security, click **Open Anyway** next to the message about OpenDisplay, and confirm. You have to do this only once.

OpenDisplay is a menu bar app: it has no Dock icon. Look for the display icon in the menu bar.

## Build and install

```sh
scripts/build-app.sh --install
```

This builds `OpenDisplay.app`, copies it to `~/Applications`, and opens it. The script signs the app with your first "Apple Development" certificate, so macOS remembers its permissions after each build. Without a certificate, it signs the app ad hoc.

For the brightness and volume keys, allow OpenDisplay in System Settings → Privacy & Security → Accessibility. The Settings window (⌘,) has a button for this.

### Screenshots

```sh
scripts/make-screenshots.sh
```

This makes the screenshots in `assets/screenshots` again: the menu (short and with all controls) and the Settings window, in light and dark mode. It takes about 30 seconds, and you must not use the mouse or keyboard while it runs. It needs an external display and [Pillow](https://pypi.org/project/pillow/) (`pip3 install pillow`). Afterwards, it restores your settings.

### Build on Linux

```sh
scripts/build-app-linux.sh --notarize
```

This builds `OpenDisplay.app` on Linux with [nix-apple-dev](https://github.com/m9tdev/nix-apple-dev) (its SDK has the macOS SDK too), signs it with a Developer ID with [rcodesign](https://github.com/indygreg/apple-platform-rs), and notarizes and staples it with an App Store Connect API key. The comment at the top of the script lists what it needs.

### Releases

```sh
scripts/make-release.sh notes.md
```

This tags the version in `Resources/Info.plist`, with the release notes in `notes.md` as the tag message, and pushes the tag. Raise the version first. The [Release workflow](.github/workflows/release.yml) then builds, signs, and notarizes the app on a self-hosted runner with `scripts/build-app-linux.sh`, and publishes the GitHub release. The signing and notary keys are secrets of the `release` environment on GitHub, which only `v*` tags can use.

To change the app icon, change the geometry in `scripts/make-app-icon.py` and `Sources/OpenDisplay/MenuBarIcon.swift`, then run `scripts/make-app-icon.py` on a Mac. It makes `Resources/AppIcon.icon`, and compiles it with Apple's `actool` into `Resources/AppIcon.compiled`, which the build copies into the app.

The compiled icon is in the repository because the Linux `actool` (from [nix-apple-dev](https://github.com/m9tdev/nix-apple-dev)) writes an iOS asset catalog for Icon Composer files, also for macOS, and macOS ignores it. When that is fixed, the build will compile the icon itself again, also on Linux.

## How it works

OpenDisplay uses private macOS APIs, because macOS has no public APIs for these features:

- `IOAVService` to send DDC/CI commands to external displays.
- `DisplayServices` for the built-in display brightness and its change notifications.
- `CGSConfigureDisplayEnabled` to turn displays on and off.
- `MonitorPanel` to rotate displays.

The app loads these APIs at runtime. If a macOS update removes one, only the feature that uses it stops working.

## License

MIT
