<p align="center">
  <img src="Resources/NextCursorIcon.png" width="128" height="128" alt="NextCursor app icon">
</p>

<h1 align="center">NextCursor</h1>

<p align="center">
  NextCursor gives macOS an adaptive (iPad-style) pointer that snaps to controls and morphs to their shape.<br>
</p>

<p align="center">
  <a href="Media/NextCursorDemo.mp4">
    <img src="Media/NextCursorDemo.gif" width="800" alt="NextCursor animated demo">
  </a>
</p>

<p align="center"><a href="Media/NextCursorDemo.mp4">Watch the full demo video</a></p>

## Highlights

- Magnetic snapping and smooth shape morphing
- Text cursor, click animation, and automatic fading
- Optional pointer inertia, disabled by default
- Multi-display, Spaces, full-screen, and full-display recording support
- Safe cursor restoration on quit, lock, or display sleep

## Download and run

[**Download NextCursor v0.1.16 for Apple Silicon →**](https://github.com/alexcybernetic/NextCursor/releases/download/v0.1.16/NextCursor-v0.1.16-macOS-arm64.zip)

Requires **macOS 13 or newer**. Unzip the download, place `NextCursor.app` where you want to keep it, and open it.

Grant access in **System Settings → Privacy & Security → Accessibility**. Add that exact app copy if it is not listed.

### If macOS blocks the app

If macOS offers **Move to Trash** or **Done**, choose **Done**. Then:

1. Open **System Settings → Privacy & Security**.
2. Scroll to **Security** and click **Open Anyway** beside the NextCursor message.
3. Authenticate when asked, then confirm **Open**.

## Build from source

Building requires Xcode Command Line Tools:

```sh
git clone https://github.com/alexcybernetic/NextCursor.git
cd NextCursor
./Scripts/build-app.sh
open Build/NextCursor.app
```

## Use

Opening NextCursor enables it. Use the menu-bar icon to toggle **Pointer Inertia** or choose **Restore System Cursor and Quit**.

Emergency toggle: **Control–Option–Command–P**

## Privacy

NextCursor works locally. No network access, no analytics, no screen capture.

It looks at the control under the pointer to find out what kind of control it is, where it is, and how big it is. It never reads text, titles, or values, and it never clicks, types, or changes anything.

## Limitations

- Snapping needs an app to expose its controls through Accessibility. Games and apps that draw their own interface do not, so the pointer stays a plain circle over them.
- Moving to another display and clicking into a window that was not active can flash the system arrow for an instant.
- Apple Silicon only.
- macOS ties Accessibility permission to the exact copy of the app. If you move it or rebuild it, grant permission again.

## License

[MIT](LICENSE)
