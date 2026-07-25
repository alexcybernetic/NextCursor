# NextCursor

Adaptive mouse cursor for the next generation.

NextCursor gives macOS an iPad-style pointer that snaps to controls, morphs to their shape, and becomes an I-beam over text. Your real click position never moves.

## Demo

<video src="Media/NextCursorDemo.mp4" poster="Media/NextCursorDemo.png" controls width="100%"></video>

[Watch the demo video](Media/NextCursorDemo.mp4)

## Highlights

- Magnetic snapping and smooth shape morphing
- Text cursor, click animation, and automatic fading
- Optional pointer inertia, disabled by default
- Multi-display, Spaces, full-screen, and full-display recording support
- Safe cursor restoration on quit, lock, or display sleep

## Install

Requires **macOS 13 or newer**. The current prebuilt release supports **Apple Silicon** Macs.

1. Download and unzip `NextCursor.app`.
2. Place it where you want to keep it, then open it.
3. Grant access in **System Settings → Privacy & Security → Accessibility**. Add the exact `NextCursor.app` copy if it is not listed.

### If macOS blocks the app

The release is not notarized, so macOS may block it the first time:

1. Try to open NextCursor once.
2. Open **System Settings → Privacy & Security**.
3. Scroll to **Security** and click **Open Anyway**.
4. Confirm **Open**, then grant Accessibility access as described above.

You only need to approve an unchanged app copy once.

## Use

Opening NextCursor enables it. Use the menu-bar icon to toggle **Pointer Inertia** or choose **Restore System Cursor and Quit**.

Emergency toggle: **Control–Option–Command–P**

## Build from source

Requires Xcode Command Line Tools:

```sh
./Scripts/build-app.sh
open Build/NextCursor.app
```

## Privacy and limitations

NextCursor works locally with no network access, analytics, or screen capture. It reads only Accessibility structure for the control beneath the pointer and never performs UI actions.

Snapping depends on each app exposing its controls through Accessibility. Games and custom canvas interfaces may remain circular.

## License

[MIT](LICENSE)
