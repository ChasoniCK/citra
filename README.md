**English** | [Русский](README.ru.md)

# Citra

A macOS menu bar utility: drag a file from Finder, hold a modifier key mid-drag, and a radial menu appears at the cursor; release the mouse button over a sector and the chosen action runs on the file. The app never opens a window.

| Modifier | Mode |
|---|---|
| ⌘ | Conversion |
| ⇧ | Tools |
| ⌃ | File Actions |

If several are held, the priority is ⌘ > ⇧ > ⌃. The menu shows only actions that work for the dragged files; if there are more than 10, it shows the first 9 and **More** with an outer arc.

## Installation

1. Download `Citra-<version>.zip` from the [Releases](../../releases) page and unzip it.
2. Drag `Citra.app` to Applications.
3. First launch. Citra isn't signed with an Apple Developer certificate, so macOS won't open it right away:
   - open Citra — a warning appears, close it;
   - System Settings → Privacy & Security → the Citra line at the bottom → **Open Anyway** → confirm.

   Or run one command in Terminal (it also helps when macOS says the app is "damaged"):

   ```bash
   xattr -dr com.apple.quarantine /Applications/Citra.app
   ```
4. A ◎ icon appears in the menu bar. The app has no window: start dragging a file from Finder, and only then hold ⌘, ⇧ or ⌃.

Requirements: macOS 26 or later, Apple Silicon or Intel (untested on Intel).

Without an Apple Developer certificate:
- after an update you may need step 3 again — to macOS it's a new app;
- macOS may deny the notification request without showing a dialog. In that case, turn them on manually: System Settings → Notifications → Citra. Results appear next to the files either way.

## Features

| Type | ⌘ Conversion | ⇧ Tools |
|---|---|---|
| Images (anything ImageIO reads: PNG, JPEG, HEIC, TIFF, GIF, BMP, WebP, AVIF…; SVG as input only) | JPEG, PNG, HEIC, TIFF, AVIF, BMP, WebP (with cwebp) — except the file's own format, PDF | Resize (presets), Rotate 90°, Compress (JPEG/HEIC only), Metadata (strip EXIF/GPS/IPTC/XMP); none for SVG |
| ZIP, TAR, TAR.GZ / TGZ | into each other (ZIP, TAR, TAR.GZ) | Extract; Test — ZIP only |
| GZ (single file) | — | Extract |
| Video AVFoundation can open (MP4, MOV, M4V) | MOV ⇄ MP4 (no re-encoding), M4A, GIF; with ffmpeg — MKV, WebM, AVI, WMV, MP3 | Compress (720p), Mute, Trim, Crop, Speed, Snapshot |
| Video AVFoundation can't open (MKV, WebM, AVI, WMV…) — ffmpeg only | MP4, MOV, MKV, WebM, AVI, WMV, GIF, MP3 (except the file's own format) | — |
| Audio (MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA…) — ffmpeg only | MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA (except the file's own format) | — |
| Subtitles SRT, VTT | SRT ⇄ VTT, TXT (plain text without tags or repeats) | — |
| PDF | — | Merge (2 or more), Split (one file per page) |

⌃ File Actions work for any files and folders: AirDrop, Float (floating shelf), Copy (⌘V in Finder pastes the files themselves), Move (asks on name conflicts), Copy Path, Terminal.

**What availability depends on:**
- **HEIC** — the ImageIO encoder (present on Apple Silicon).
- **TAR, TAR.GZ and archive conversion** — `/usr/bin/tar`; single GZ — `/usr/bin/gzip`. An archive with `..` paths is neither extracted nor converted.
- **WebP** — `cwebp` in the same folders as ffmpeg (`brew install webp`): ImageIO only reads WebP.
- **SVG** is rasterized with the long side at least 1024 px.
- **OGG** — ffmpeg's built-in experimental Vorbis encoder (the Homebrew build has no libvorbis): always stereo, lower quality than libvorbis. Album art isn't carried over when converting audio; WAV and AIFF are 16-bit.
- **ffmpeg formats** — `ffmpeg` in `/opt/homebrew/bin` or `/usr/local/bin` and the encoders it needs. ffmpeg isn't bundled with the app; its status and a hint are in Settings → Conversions.
- **Terminal / iTerm2** — what's selected in settings and installed on the Mac.
- **M4A and Mute for video without audio, Split for a single-page PDF** — Citra doesn't read files before the drop, so that macOS doesn't ask for folder access. That's why these actions are always shown; on drop they report why they didn't work and create nothing.

The result goes next to the original or into a chosen folder: `video.mp4` → `video.mov`, tools — `photo rotated.png`, a taken name → `video 2.mov`. The original is never changed (except by Move). Output is written to a temporary file and renamed when done: cancelling or an error leaves no broken files. Task progress and cancellation are in the menu bar menu.

## Settings

Menu bar → Settings… (⌘,):
- **General** — on/off, launch at login, notifications, where to save results.
- **Shortcuts** — the modifier for each mode.
- **Appearance** — ring size, animations, accent color.
- **Conversions** — JPEG/HEIC quality, MOV mode, available conversions.
- **File Actions** — Terminal or iTerm2, shelf edge.

## Building

Requires Xcode 26+ and XcodeGen (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -project Citra.xcodeproj -scheme Citra -destination 'platform=macOS' test
xcodebuild -project Citra.xcodeproj -scheme Citra -configuration Debug build
```

Build into the default DerivedData (no `-derivedDataPath` inside the project): if the folder is synced by iCloud Drive, codesign rejects the bundle because of extended attributes.

By default the build is ad-hoc signed, so anyone can build the project. To sign your own builds with an Apple Development certificate (a stable signature keeps the notification permission across rebuilds), create `Config/Signing.local.xcconfig` — git ignores it:

```
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = <your Team ID>
```

## Release

```bash
scripts/release.sh
```

The script builds a universal (Apple Silicon + Intel) ad-hoc-signed Release build, verifies the signature and packs it with `ditto` into `dist/Citra-<version>.zip`. Your personal certificate never ends up in the release, even if `Signing.local.xcconfig` exists. The version is set in `project.yml` (`CFBundleShortVersionString`). Publishing:

```bash
gh release create v1.0.0 dist/Citra-1.0.0.zip --title "Citra 1.0.0" --notes "…"
```

## Permissions and sandbox

- App Sandbox is **off** — deliberately, for direct distribution (Developer ID): the app needs global mouse monitoring, writing results next to the original in any folder, and running system tools (`/usr/bin/tar`, later an external `ffmpeg`).
- Accessibility, Input Monitoring, Full Disk Access and Automation are **not needed**: the drag start is caught by a global mouse monitor, modifiers and Escape are read by polling state, and Terminal is opened through Launch Services without AppleScript.
- **Notifications** are requested on the first finished result (not at launch); without them the result still appears next to the original.
