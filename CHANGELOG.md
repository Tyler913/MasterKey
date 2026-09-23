# Changelog

## 1.4 — Build 6

- Add independent Dock and menu bar visibility settings, both disabled by default.
- Support background operation with both icons hidden; reopening the app displays settings.
- Show a mouse symbol and MK label in the menu bar, and synchronize the setting when macOS removes the item.
- Reload and redraw the bundled Dock icon after activation-policy changes to avoid the generic placeholder.
- Add a Quit action to the settings window.
- Standardize installation at `/Applications/MasterKey.app` and package builds as a single ZIP without leaving runnable preview or backup copies.

## 1.3 — Build 4

- Record shortcut combinations directly from the keyboard, including left and right modifiers.
- Add a menu bar visibility setting. The mutually exclusive Dock/menu bar behavior in this version is replaced by independent settings in 1.4.

## 1.2 — Build 3

- Add English, Simplified Chinese, Traditional Chinese, and system language selection.
- Simplify settings and move detailed instructions and diagnostics into separate panels.
- Add the application icon.

## 1.1 — Build 2

- Add shared HID++ monitoring for Logitech buttons that are absent from standard mouse reports, including the tested MX Master 4 side button.

## 1.0 — Build 1

- Initial native Swift application with Fn output, sided modifier combinations, and an Options+ relay mode.
