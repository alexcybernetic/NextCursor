# NextCursor

An iPad-style adaptive pointer for macOS.

NextCursor replaces the arrow with a soft circular pointer that:

- magnetically settles into accessible buttons, links, menu items, and controls;
- morphs to the control's shape;
- changes to an I-beam over text;
- compresses while clicking;
- offers session-only optional pointer inertia;
- fades after inactivity; and
- works across displays, Spaces, and full-screen apps.

The physical hit point always remains inside the hovered control. Only the rendered pointer settles into the control, so clicks keep their native macOS behavior and NextCursor never warps the mouse or invokes UI actions.

## Why Accessibility permission is required

macOS does not expose iPadOS's adaptive pointer system. NextCursor uses the macOS Accessibility API to read structural metadata—role, bounds, enabled state, hierarchy, and available action names—for the element directly beneath the pointer. It does not read element labels or values, perform actions, capture the screen, access the network, or collect analytics.

The app will not replace the system cursor until Accessibility access has been granted.

## Build and run

Requirements: macOS 13 or newer and Xcode Command Line Tools.

```sh
./Scripts/build-app.sh
open Build/NextCursor.app
```

This creates a portable app at `Build/NextCursor.app`; it is not installed or copied anywhere. After building once, start it again by double-clicking that same app in Finder or by running:

```sh
open Build/NextCursor.app
```

Use `./Scripts/run.sh` only when you explicitly want to rebuild and run a debug version.

Grant **NextCursor Portable** access in **System Settings → Privacy & Security → Accessibility** when prompted. The portable build has its own bundle identity, so it does not conflict with entries from older installed copies. Because development builds are ad-hoc signed, macOS may ask again after the executable changes, but not each time the unchanged app starts.

## Quit or recover

Use the checked **Pointer Inertia** menu item to enable or disable free-pointer smoothing for the current session. Choose **Restore System Cursor and Quit** to return immediately to the default macOS pointer. The emergency toggle is **Control–Option–Command–P**. Normal quit, session lock, and display sleep all restore the native pointer before removing the overlay. NextCursor saves no enabled state, creates no login item, and changes no persistent cursor setting.

If the process is force-killed and macOS does not restore the pointer automatically, run:

```sh
swift Scripts/restore-system-cursor.swift
```

## Current platform limitation

Snapping depends on the target app exposing controls through macOS Accessibility. Standard AppKit, SwiftUI, Catalyst, and most browser controls work; games and custom canvas-based interfaces may expose no target to morph into. In those areas, NextCursor remains circular.

## License

NextCursor is available under the [MIT License](LICENSE).
