# WindowDock

WindowDock is an early native macOS menu-bar window docking prototype inspired by FancyZones. It provides several built-in layouts and docks the window being dragged into the highlighted zone.

## Current behavior

1. Launch WindowDock and grant Accessibility access when macOS asks.
2. Open the menu-bar icon and choose a layout for the display named in the menu.
3. Drag a normal, resizable application window by its title bar.
4. Hold **Shift** while dragging to reveal the zones on the current display.
5. Release over a highlighted zone to dock the window.

The built-in layouts are Two Columns, Three Columns, Main + Stack, Four Quadrants, and Two Thirds + One Third. The selection is saved independently for each connected display using its persistent display UUID.

The app uses each display's usable frame, so zones avoid the menu bar and Dock. The status-bar menu can temporarily disable docking or request Accessibility access again. To configure a particular display, move the pointer to that display before opening the WindowDock menu.

## Custom layouts

Open the layout submenu and choose **Create Custom from Current…**. If the selected profile is already custom, the command is **Edit Current Layout…**.

In the editor:

- Rename the profile in the Name field.
- Click a zone to make it the highlighted active zone.
- Drag inside the active zone to move it on a 5% grid.
- Drag any white edge or corner handle to resize that side independently.
- Split the active zone into two adjacent zones, up to 12 total zones.
- Delete the active zone when the layout has more than one zone.
- Adjust the gap slider to control spacing between docked windows.
- Save the layout to persist it and select it for the targeted display.

Overlapping zones turn red and disable Save until the overlap is resolved. This prevents a profile that looks plausible in the editor from producing ambiguous docking targets.

Saved profiles appear under **Custom Profiles** and can be selected on any display.

## Requirements

- macOS 13 or newer
- Xcode with its matching macOS SDK, or a matching installation of Apple Command Line Tools

The Swift compiler and macOS SDK must come from the same Apple developer-tools release. If they do not match, Swift reports that the SDK is unsupported by the compiler; update Xcode/Command Line Tools and select the matching installation with `xcode-select`.

## Build and launch

Create a local app bundle:

```sh
./scripts/package-app.sh
open dist/WindowDock.app
```

Or run the development executable directly:

```sh
swift run WindowDock
```

On a machine where the selected Command Line Tools compiler does not match its default SDK, but the macOS 15.4 fallback SDK is installed, use:

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ./scripts/package-app.sh
```

The packaging script builds a release binary, creates `dist/WindowDock.app`, and applies an ad-hoc signature suitable for local development. Production distribution will require an Apple Developer ID signature and notarization.

Run `swift test` from a full matching Xcode installation to execute the geometry test suite.

## Permissions

WindowDock needs Accessibility access to identify, move, and resize windows belonging to other applications. If docking does not activate:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. If WindowDock is already present but the app still asks for access, remove that stale entry with the minus button.
3. Add the current `dist/WindowDock.app` with the plus button and enable it.
4. Quit and reopen WindowDock if macOS does not apply the change immediately.

Local packages use a stable development-only designated requirement so rebuilding the same bundle does not replace its Accessibility identity with a new binary hash. Production distribution will replace the ad-hoc signature with an Apple Developer ID signature.

No window contents, keystrokes, or mouse events are persisted.

## Project structure

- `Sources/DockCore`: normalized zone geometry and coordinate conversion
- `Sources/WindowDock`: menu-bar app, Accessibility integration, drag monitor, and overlay
- `Tests/DockCoreTests`: deterministic geometry tests
- `Resources/Info.plist`: application bundle metadata
- `scripts/package-app.sh`: local release bundle builder

## Next milestones

- Add profile duplication, deletion, and import/export.
- Add configurable activation modifiers and keyboard docking shortcuts.
- Harden behavior for Spaces, Stage Manager, display changes, and applications with minimum window sizes.
