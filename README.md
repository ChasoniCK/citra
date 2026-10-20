**English** | [Русский](README.ru.md)

# Citra

Citra is a macOS menu bar utility. Drag a file from Finder, hold a modifier key mid-drag, and a radial menu appears at the cursor. Release the mouse button over a sector and Citra runs that action on the file. There is no main window.

| Modifier | Mode |
|---|---|
| ⌘ | Conversion |
| ⇧ | Tools |
| ⌃ | File Actions |

If you hold more than one, ⌘ wins over ⇧, and ⇧ over ⌃. The menu shows only the actions that work for the dragged files. When there are more than 10, you get the first 9 plus More, which shows the rest on an arc outside the ring.

## Installation

1. Download `Citra-<version>.zip` from the [Releases](../../releases) page and unzip it.
2. Drag `Citra.app` to Applications.
3. Citra isn't signed with an Apple Developer certificate, so macOS won't open it on the first try:
   - open Citra and close the warning that appears;
   - go to System Settings → Privacy & Security, find the Citra line at the bottom, click **Open Anyway** and confirm.

   You can also run one command in Terminal. It helps when macOS says the app is "damaged", too:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Citra.app
   ```
4. A ◎ icon appears in the menu bar. Start dragging a file from Finder, and only then hold ⌘, ⇧ or ⌃.

Requirements: macOS 26 or later, Apple Silicon or Intel (untested on Intel).

Since the app has no Apple Developer signature, macOS treats every update as a new app, and you may need step 3 again. macOS may also deny the notification request without showing a dialog. If that happens, turn notifications on in System Settings → Notifications → Citra. Results appear next to the files either way.

## Features

| Type | ⌘ Conversion | ⇧ Tools |
|---|---|---|
| Images (anything ImageIO reads: PNG, JPEG, HEIC, TIFF, GIF, BMP, WebP, AVIF…; SVG as input only) | JPEG, PNG, HEIC, TIFF, AVIF, BMP, WebP (with cwebp), PDF, except the file's own format | Resize (presets), Rotate 90°, Compress (JPEG/HEIC only), Metadata (strip EXIF/GPS/IPTC/XMP); none for SVG |
| ZIP, TAR, TAR.GZ / TGZ | into each other (ZIP, TAR, TAR.GZ) | Extract; Test (ZIP only) |
| GZ (single file) | — | Extract |
| Video AVFoundation can open (MP4, MOV, M4V) | MOV ⇄ MP4 (no re-encoding), M4A, GIF; with ffmpeg also MKV, WebM, AVI, WMV, MP3 | Compress (720p), Mute, Trim, Crop, Speed, Snapshot |
| Other video (MKV, WebM, AVI, WMV…), needs ffmpeg | MP4, MOV, MKV, WebM, AVI, WMV, GIF, MP3, except the file's own format | — |
| Audio (MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA…), needs ffmpeg | MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA, except the file's own format | — |
| Subtitles SRT, VTT | SRT ⇄ VTT, TXT (plain text without tags or repeats) | — |
| PDF | — | Merge (2 or more), Split (one file per page) |

⌃ File Actions work on any files and folders: AirDrop, Float (floating shelf), Copy (⌘V in Finder pastes the files themselves), Move (asks on name conflicts), Copy Path, Terminal.

Some actions depend on the system or on external tools:
- HEIC needs the ImageIO encoder, which Apple Silicon Macs have.
- TAR, TAR.GZ and archive conversion use `/usr/bin/tar`; a single GZ uses `/usr/bin/gzip`. Citra won't extract or convert an archive that contains `..` paths.
- WebP output needs `cwebp` (`brew install webp`) in the same folders as ffmpeg, because ImageIO only reads WebP.
- SVG is rasterized so the long side is at least 1024 px.
- OGG uses ffmpeg's built-in experimental Vorbis encoder, since the Homebrew build has no libvorbis. The output is always stereo and sounds worse than libvorbis would. Audio conversion doesn't carry over album art, and WAV and AIFF come out 16-bit.
- The ffmpeg formats need `ffmpeg` in `/opt/homebrew/bin` or `/usr/local/bin`, with the encoders they use. ffmpeg isn't bundled with the app; Settings → Conversions shows its status and a hint.
- The Terminal action opens Terminal or iTerm2, depending on what's selected in Settings and installed on the Mac.
- M4A and Mute show up even for video without audio, and Split for a single-page PDF. Citra doesn't read files before the drop, so macOS doesn't ask for folder access. When one of these actions can't apply, it says why and creates nothing.

Results go next to the original or into a folder you choose. A conversion changes the extension (`video.mp4` → `video.mov`), a tool adds a word to the name (`photo rotated.png`), and a taken name gets a number (`video 2.mov`). Only Move touches the original. Citra writes to a temporary file and renames it when done, so a cancelled or failed task leaves no broken files. The menu bar menu shows task progress and lets you cancel.

## Settings

Menu bar → Settings… (⌘,):
- General: on/off, launch at login, notifications, where to save results.
- Shortcuts: the modifier for each mode.
- Appearance: ring size, animations, accent color.
- Conversions: JPEG/HEIC quality, MOV mode, available conversions.
- File Actions: Terminal or iTerm2, shelf edge.

## Building

You need Xcode 26+ and XcodeGen (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -project Citra.xcodeproj -scheme Citra -destination 'platform=macOS' test
xcodebuild -project Citra.xcodeproj -scheme Citra -configuration Debug build
```

Build into the default DerivedData and don't point `-derivedDataPath` inside the project. If the project folder is synced by iCloud Drive, codesign rejects the bundle because of extended attributes.

Builds are ad-hoc signed by default, so anyone can build the project. A stable signature keeps the notification permission across rebuilds, so if you want to sign your builds with an Apple Development certificate, create `Config/Signing.local.xcconfig` (git ignores it):

```
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = <your Team ID>
```

## Release

```bash
scripts/release.sh
```

The script makes a universal (Apple Silicon + Intel) ad-hoc-signed Release build, verifies the signature and packs the app with `ditto` into `dist/Citra-<version>.zip`. Your personal certificate stays out of the release even if `Signing.local.xcconfig` exists. The version lives in `project.yml` (`CFBundleShortVersionString`). To publish:

```bash
gh release create v1.0.0 dist/Citra-1.0.0.zip --title "Citra 1.0.0" --notes "…"
```

## Permissions and sandbox

App Sandbox is off on purpose. Citra is meant for direct distribution (Developer ID), and it has to monitor the mouse globally, write results next to the original in any folder, and run command-line tools such as `/usr/bin/tar` and an external `ffmpeg`.

Citra doesn't need Accessibility, Input Monitoring, Full Disk Access or Automation. A global mouse monitor catches the start of a drag, Citra polls the modifier keys and Escape, and Terminal opens through Launch Services without AppleScript.

Citra asks for notification permission when the first result is ready, not at launch. Without it, results still appear next to the original.
