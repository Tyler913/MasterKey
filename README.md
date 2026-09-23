# MasterKey

<img src="Resources/AppIcon.png" width="112" alt="MasterKey app icon">

A lightweight native macOS utility that turns a Logitech mouse button into a Typeless voice shortcut. Send Fn or a key combination with explicit left and right modifiers while keeping Logi Options+ running.

## Features

- Shared Logitech mouse input, including HID++ button reports used by the MX Master 4.
- Fn output and combinations with left or right Control, Command, Option, and Shift.
- Click-to-toggle and hold-to-talk behavior, subject to the selected input mode and Typeless settings.
- Click a shortcut field and press the physical keys to configure a combination.
- Independent Dock and menu bar visibility, both off by default.
- English, Simplified Chinese, Traditional Chinese, and automatic system language selection.
- Optional launch at login. No third-party dependencies, network access, or microphone access.

## Requirements

- macOS 13 or later.
- Swift 5.9 or later, provided by Xcode or the Xcode Command Line Tools, to build from source.
- Accessibility permission to send shortcuts, plus Input Monitoring for direct mouse input.
- Typeless configured to use the same shortcut as MasterKey.

The direct Logitech path has been confirmed on an MX Master 4 with a USB receiver while Options+ remains running. Other devices, buttons, transports, and Typeless versions may behave differently. See [Testing](docs/TESTING.md) for coverage and limitations.

## Build and install

From the project directory:

```sh
bash scripts/check.sh
bash scripts/build.sh
```

The build creates `dist/MasterKey.zip`. To build and install at the canonical application path, first quit any running MasterKey instance, then run:

```sh
bash scripts/install.sh
```

The installer uses `/Applications/MasterKey.app` and opens it when finished. Use `bash scripts/install.sh --no-open` to install without launching. Avoid keeping multiple runnable copies of the app.

The scripts use local ad hoc signing, without Developer ID signing or notarization. Rebuilding may require removing and re-adding MasterKey in macOS privacy permissions, then relaunching it. The build targets the current machine's architecture.

## Connect your mouse

### Logitech direct input

1. Keep Logi Options+ running. Assign the target button to **Other actions → Do nothing**. Check both the global profile and any app-specific overrides. An empty **Keyboard shortcut** field displaying **None** is a different setting.
2. Open MasterKey and grant the requested permissions. Relaunch if macOS requests it, then select **Reconnect**.
3. Choose **Logitech · Direct**, click **Record**, and press the target button within 15 seconds. Recording does not send a shortcut.
4. Select **Fn / 🌐**, or record a key combination that matches the shortcut in Typeless.
5. Use **Click** for a complete key press on each mouse click, or **Hold to talk** when the input and Typeless configuration support it. Typeless controls when dictation starts and stops.

Direct mode listens to standard Logitech button reports and the vendor-specific HID++ channel. It opens devices without exclusive access and only sends capability queries (`GetFeature`, `GetCount`, and `GetCidInfo`). It does not install a driver or change Options+ button mappings, diversion, or gesture settings.

The receiver may appear as **USB Receiver**. Re-record the button after changing pairing, receiver, USB port, or transport. Primary and secondary mouse buttons cannot be assigned.

### Options+ relay

If a button cannot be recorded directly:

1. Choose **Options+ · Relay** in MasterKey. The default relay key is **F18**.
2. Assign that same keyboard shortcut to the mouse button in Options+.
3. If your keyboard has no F18 key, click **Record in Options+…**, then focus the Options+ shortcut field within three seconds. MasterKey sends the relay key for Options+ to record.
4. Choose the output shortcut that matches Typeless.

Relay mode supports clicks only, because Options+ may not preserve physical hold duration. The relay shortcut is consumed while the bridge is active; choose a shortcut that other apps do not need. Input matching uses generic modifier flags, while output can distinguish left and right keys. The relay and output shortcuts must differ.

### System mouse input

**System mouse button** mode handles side-button events already exposed by macOS. It matches the same button number on every mouse and suppresses that button's original action. Unlike Logitech direct input, it cannot identify the physical device.

## Settings and background operation

- To configure a **Key combination**, click the shortcut field and press the desired physical keys. Left and right modifiers are captured separately; pressing the main key saves the combination. Escape cancels. For Fn alone, select **Fn / 🌐** instead.
- **Show Dock icon** and **Show menu bar icon** are independent. Enable either, both, or neither. Both start disabled and retain your choices afterward.
- Closing the settings window keeps MasterKey running. With both icons hidden, open MasterKey again from Applications or Spotlight to return to settings.
- Normal launches show settings; login launches stay in the background. Use **Quit MasterKey** in settings to stop the app.
- Change **Language** to switch the interface immediately. Setup help and event diagnostics are available from the window footer.

## Troubleshooting

If Fn does not activate Typeless, select **Key combination** and record a sided shortcut, such as Left Control + Left Command + Z. Add the identical shortcut in Typeless under **Settings → Keyboard shortcuts**. Use **Test** and focus Typeless or a text field during the three-second countdown to check output separately from mouse input.

MasterKey sends Quartz keyboard events rather than emulating a hardware keyboard. An event shown as sent does not prove that Typeless accepted it. Also check whether the macOS Globe-key action conflicts with your existing Typeless setup.

If permissions stop working after an update, remove and re-add `/Applications/MasterKey.app` in the affected privacy permission lists and relaunch it. For missing direct input, check the Options+ action and the HID++ connection in **Diagnostics**, or use the relay mode.

## Privacy and key release

- No network calls, microphone capture, typed-text logging, or access to Typeless history.
- Preferences stay on the Mac. Diagnostics retain up to 80 recent connection and button events in memory; copying the log is an explicit action.
- Held shortcuts are released on mouse release, disconnect, pause, configuration changes, listener interruption, sleep, session changes, and normal quit, with a 120-second hold limit.
- Shortcut output is skipped while physical keyboard modifiers are held. Release them before pressing the mouse button.
- **Release keys** provides manual recovery. Cleanup cannot be guaranteed after a crash, forced termination, or permission revocation.

## Development

Open `Package.swift` in Xcode or use the shell scripts. The verification executable does not require XCTest and does not post keyboard events. See [Testing](docs/TESTING.md) for automated and manual checks.

| Path | Purpose |
| --- | --- |
| `Sources/BridgeCore/` | Configuration, keyboard plans, shortcut capture, HID++ parsing, localization |
| `Sources/MasterKey/` | Native application, UI, device monitoring, event output |
| `Tests/BridgeCoreTests/` | Standalone verification executable |
| `Resources/` | Bundle metadata, localized permission strings, icon assets |
| `scripts/` | Build, install, icon generation, and diagnostic tools |
| `docs/` | Testing documentation |

The version and build number live in `Resources/Info.plist`; release history is in [CHANGELOG.md](CHANGELOG.md). Icon source and provenance are documented in [Resources/Artwork.md](Resources/Artwork.md). To regenerate the bundled icon:

```sh
bash scripts/build-icon.sh
```

The [.gitignore](.gitignore) excludes build caches, generated app bundles and installers, `dist/`, local IDE state, Finder metadata, logs, and local signing material. Source code, tests, scripts, documentation, and both icon assets belong in Git. Simplified and Traditional Chinese strings are intentional application localization resources; project documentation and code comments are in English.

Generated ZIP files belong in GitHub Releases if you choose to distribute builds, rather than in the source tree. Temporary packaging directories are removed automatically. Development previews render images directly and do not create additional installed apps.

## Uninstall

Disable **Launch at login**, quit MasterKey, and move `/Applications/MasterKey.app` to the Trash. Remove its privacy permission entries if desired. No Logitech device settings need to be restored.

## References

- [Apple: IOHIDManagerOpen](https://developer.apple.com/documentation/iokit/iohidmanageropen)
- [Apple: Quartz keyboard event creation](https://developer.apple.com/documentation/coregraphics/cgevent/init(keyboardeventsource:virtualkey:keydown:))
- Apple SDK: `IOKit/hidsystem/IOLLEvent.h` for sided modifier flags.
- [Typeless settings guide](https://www.typeless.com/help/quickstart/settings)
- [Logitech HID++ 2.0 documentation](https://github.com/Logitech/cpg-docs/blob/master/hidpp20/README.rst)
- [HID++ feature 0x1B04 reference](https://lekensteyn.nl/files/logitech/x1b04_specialkeysmsebuttons.html)
