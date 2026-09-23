# Testing

## Automated checks

Run from the project root:

```sh
bash scripts/check.sh
```

This runs `BridgeChecks`, a standalone Swift executable that works with the Command Line Tools without XCTest. The 21 checks cover:

- Physical shortcut capture, including left and right modifiers, common keys, and saved-setting compatibility.
- System language selection, translation completeness, formatting arguments, and configuration stability across languages.
- Fn press/release, sided modifier flags, all 81 modifier combinations, and Quartz event serialization.
- Duplicate HID reports, disconnect reset, relay matching, and loop prevention.
- HID binding identity and configuration persistence.
- Captured MX Master 4 HID++ button reports, malformed-report rejection, control filtering, simultaneous buttons, and receiver-slot isolation.

These checks do not post keyboard events or activate Typeless. Build and verify the application bundle separately:

```sh
bash scripts/build.sh
```

The build script verifies the ad hoc signature before creating `dist/MasterKey.zip`. It does not install or launch the app.

## UI previews

Render the settings UI using fixture data:

```sh
swift run --build-system native MasterKey --render-previews .build/previews
```

The debug renderer covers English, Simplified Chinese, and Traditional Chinese in Fn, key-combination, relay, and missing-permission states. It does not monitor hardware, send shortcuts, or change the user's binding configuration. Preview images are generated artifacts and are excluded from Git.

## Manual acceptance checks

Use a correctly permissioned installation and keep Logi Options+ running:

1. Set the target button to **Other actions → Do nothing**, then record it in **Logitech · Direct** mode.
2. Verify that two clicks start and stop Typeless dictation with the matching shortcut. Check hold/release separately when using hold-to-talk.
3. Record left and right modifier combinations with a physical keyboard. Confirm that Escape cancels without changing the saved shortcut.
4. Test **Options+ · Relay**, including the delayed relay-key recording flow. Confirm one output press per click.
5. Toggle Dock and menu bar visibility independently through all four combinations. Check the actual icons, not just the preference values or `NSStatusItem.isVisible`.
6. With both icons hidden, close settings and reopen MasterKey from Applications or Spotlight. Verify that settings reopen and the visibility choices survive a restart.
7. Switch all three interface languages. Check labels, help, diagnostics, and shortcut recording.
8. Confirm that pause, disconnect, and normal quit release held output keys. Verify that other Options+ buttons, scrolling, and gestures still work.
9. Check launch-at-login behavior separately from an ordinary app launch.

## Hardware diagnostics

The installed app includes a 15-second HID++ probe:

```sh
/Applications/MasterKey.app/Contents/MacOS/MasterKey --probe-hidpp
```

It queries button capabilities and prints button transitions without posting keyboard shortcuts or changing device configuration. A lower-level 45-second capability probe is also available as `scripts/inspect-hidpp.swift`:

```sh
swift scripts/inspect-hidpp.swift
```

These probes require access to the relevant HID interfaces. Prefer the installed app's Diagnostics panel for ordinary troubleshooting. Do not commit local logs, preference exports, or diagnostic snapshots.

## Recorded coverage

Version 1.4 (build 6) passed all 21 checks and a release build with strict signature verification on Apple Silicon using macOS 27.2 and Swift 6.4.

The development machine's MX Master 4 reported the tested side button as control ID `0x00C3` over a Logitech USB receiver while Options+ remained active. Direct input and Typeless activation were confirmed in actual use. The final menu bar and Dock icons were visually confirmed, and both visibility settings remained off across a restart. The saved mouse and keyboard configuration was preserved during the update.

This is evidence for the tested setup, not a compatibility guarantee for every Logitech device or macOS/Typeless release. Right-side physical modifier behavior has automated mapping coverage; the desktop automation used for UI checks generated generic left-side modifier events. Privacy permissions may need to be re-established after ad hoc-signed updates, so actual dictation must be checked separately from successful compilation or event emission.
