# WindowDock

WindowDock is a native macOS menu-bar window manager inspired by FancyZones. It
divides each display into zones and snaps windows into them, either by dragging a
window onto a zone or with a keyboard shortcut.

The repository is named `macos-window-manager`; the app itself is WindowDock.

## Current behavior

1. Launch WindowDock and grant Accessibility access when macOS asks.
2. Open the menu-bar icon and choose a layout for the display named in the menu.
3. Drag a normal, resizable application window by its title bar.
4. Hold the activation modifier (**Shift** by default) while dragging to reveal the
   zones on the current display.
5. Release over a highlighted zone to dock the window.

The built-in layouts are Two Columns, Three Columns, Main + Stack, Four Quadrants,
and Two Thirds + One Third. The selection is saved independently for each connected
display using its persistent display UUID.

The app uses each display's usable frame, so zones avoid the menu bar and Dock. The
status-bar menu can temporarily disable docking or request Accessibility access
again. To configure a particular display, move the pointer to that display before
opening the WindowDock menu.

## Keyboard shortcuts

Docking also works without the mouse. The shortcuts are global and apply to the
frontmost window, using the layout selected for the display that window is on.

| Shortcut | Action |
| --- | --- |
| `⌃⌥1` … `⌃⌥9` | Dock the focused window in zone 1–9 |
| `⌃⌥←` `⌃⌥→` `⌃⌥↑` `⌃⌥↓` | Move the focused window to the neighbouring zone |
| `⌃⌥Z` | Restore the last docked window to where it was before |

Arrow movement only travels to a zone that actually sits in that direction and
shares an edge span with the current zone, so `⌃⌥↓` from a top-right zone lands in
the zone directly below it rather than jumping across the display. A window that is
not in a zone yet snaps into the nearest zone on the first press.

`⌃⌥Z` walks back through the most recent docks, restoring each window to the frame
it had before WindowDock moved it.

Shortcuts are registered with the Carbon hot key API, which reserves the
combination system-wide, so they never reach the frontmost application. Turn them
off in **Keyboard Shortcuts → Enable Keyboard Shortcuts** if they collide with
something else; combinations already claimed by another app are reported in the
menu's status line at launch.

## Activation modifier

**Drag Activation** in the menu chooses which modifier reveals the zones while
dragging: Shift, Control, Option, Command, or no modifier at all. Choosing *No
modifier* shows the zones for every window drag.

## Custom layouts

Open the layout submenu and choose **New Custom Profile from Current…**. If the
selected profile is already custom, **Edit Current Custom Profile…** reopens it, and
**Duplicate Current Profile** copies any profile — including a built-in one — into a
new editable custom profile.

In the editor:

- Rename the profile in the Name field.
- Click a zone to make it the highlighted active zone.
- Drag inside the active zone to move it on a 5% grid.
- Drag any white edge or corner handle to resize that side independently.
- Split the active zone into two adjacent zones, up to 12 total zones.
- Delete the active zone when the layout has more than one zone.
- Adjust the gap slider to control spacing between docked windows.
- Save the layout to persist it and select it for the targeted display.

Overlapping zones turn red and disable Save until the overlap is resolved. This
prevents a profile that looks plausible in the editor from producing ambiguous
docking targets.

Saved profiles appear under **Custom Profiles** and can be selected on any display.

## Sharing profiles

**Export Custom Profiles…** writes every custom profile to a versioned JSON file.
**Import Profiles…** reads one back.

Import never overwrites what is already on the Mac: each imported profile is given a
fresh identifier, and a name that collides with an existing profile is numbered
(`Editing 2`). Layouts that fail validation — overlapping zones, zones outside the
display, duplicate zone identifiers — are skipped rather than imported.

## Requirements

- macOS 13 or newer
- Xcode with its matching macOS SDK, or a matching installation of Apple Command
  Line Tools

The Swift compiler and macOS SDK must come from the same Apple developer-tools
release. If they do not match, Swift reports that the SDK is unsupported by the
compiler; update Xcode/Command Line Tools and select the matching installation with
`xcode-select`.

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

On a machine where the selected Command Line Tools compiler does not match its
default SDK, but the macOS 15.4 fallback SDK is installed, use:

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ./scripts/package-app.sh
```

The packaging script builds a release binary, creates `dist/WindowDock.app`, and
applies an ad-hoc signature suitable for local development. Production distribution
will require an Apple Developer ID signature and notarization.

Run `swift test` to execute the geometry, navigation, and profile-archive test
suites. The same build and test steps run in CI on every push and pull request.

## Permissions

WindowDock needs Accessibility access to identify, move, and resize windows
belonging to other applications. If docking does not activate:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. If WindowDock is already present but the app still asks for access, remove that
   stale entry with the minus button.
3. Add the current `dist/WindowDock.app` with the plus button and enable it.
4. Quit and reopen WindowDock if macOS does not apply the change immediately.

Local packages use a stable development-only designated requirement so rebuilding
the same bundle does not replace its Accessibility identity with a new binary hash.
Production distribution will replace the ad-hoc signature with an Apple Developer ID
signature.

No window contents, keystrokes, or mouse events are persisted.

## Project structure

- `Sources/DockCore`: normalized zone geometry, coordinate conversion, zone
  navigation, activation modifiers, and the profile archive format
- `Sources/WindowDock`: menu-bar app, Accessibility integration, drag monitor,
  global shortcuts, and overlay
- `Tests/DockCoreTests`: deterministic geometry, navigation, and archive tests
- `Resources/Info.plist`: application bundle metadata
- `scripts/package-app.sh`: local release bundle builder
- `.github/workflows/ci.yml`: build and test on every push

`DockController` owns the docking model shared by the pointer and keyboard paths;
`WindowDragMonitor` handles drags, `HotkeyCenter` handles shortcuts, and both dock
through `WindowSnapper`, which records the previous frame so a dock can be undone.

## Known limitations

- Windows that report a minimum size larger than the target zone move but do not
  shrink to fit; the menu reports when this happens.
- Native full-screen and minimized windows are skipped, since they ignore position
  and size changes.
- Stage Manager and per-Space window behavior have not been exercised in depth.

## Next milestones

- User-configurable shortcut combinations rather than the fixed `⌃⌥` set.
- Cycle between windows already docked in the same zone.
- Remember and restore whole window arrangements per display configuration.
- Apple Developer ID signing and notarization for distribution outside this repo.
