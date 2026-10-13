<img src="assets/icon.png" width="128" height="128" alt="OpenDisplay icon">

# OpenDisplay

A free macOS menu bar app to control your displays. It looks and works like the system Sound and Wi-Fi menus.

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

## How it works

OpenDisplay uses private macOS APIs, because macOS has no public APIs for these features:

- `IOAVService` to send DDC/CI commands to external displays.
- `DisplayServices` for the built-in display brightness and its change notifications.
- `CGSConfigureDisplayEnabled` to turn displays on and off.
- `MonitorPanel` to rotate displays.

The app loads these APIs at runtime. If a macOS update removes one, only the feature that uses it stops working.

## License

MIT
