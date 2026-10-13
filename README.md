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

To change the app icon, change the geometry in `scripts/make-app-icon.py` and `Sources/OpenDisplay/MenuBarIcon.swift`, then run `scripts/make-app-icon.py`.

## How it works

OpenDisplay uses private macOS APIs, because macOS has no public APIs for these features:

- `IOAVService` to send DDC/CI commands to external displays.
- `DisplayServices` for the built-in display brightness and its change notifications.
- `CGSConfigureDisplayEnabled` to turn displays on and off.
- `MonitorPanel` to rotate displays.

The app loads these APIs at runtime. If a macOS update removes one, only the feature that uses it stops working.

## License

MIT
