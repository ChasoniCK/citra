# Stage 3 — Types, Registries, First Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the PoC sector lists with real, registered actions in the spec's order: images → image tools → ZIP extract/test → ZIP → TAR / TAR.GZ → video → File Actions, each running on real files with progress, cancellation, errors and a completion notice.

**Architecture:** `FileTypeResolver` turns dropped URLs into `FileItem`s (UTType from content, then metadata, then extension). Every action conforms to one `FileAction` protocol; three static registries (conversion, tools, file actions) answer "what applies to these items", so the ring, the center text and later the settings read from the registries only. `TaskManager` runs actions off the main thread, tracks `Progress`, cancels, reports errors and posts a "Show in Finder" notification. Outputs go through one `OutputWriter` (temp file in the target folder, atomic move to a free Finder-style name).

**Tech Stack:** Swift 6, ImageIO, PDFKit, AVFoundation, Compression (raw DEFLATE), `/usr/bin/tar`, UserNotifications, AppKit (sharing, open panel, shelf panel), Swift Testing.

## Global Constraints

- The original is never modified or deleted (only Move, explicitly chosen).
- Output next to the original: conversions `name.ext`, same-format tools `name <suffix>.ext` (`photo rotated.png`), collisions `name 2.ext`; written to a hidden temp file in the same folder and renamed, so a failure or cancel leaves nothing half-written.
- Only actions that really work for the dropped items appear; `isAvailable` hides actions whose encoder/tool is missing.
- Errors are never swallowed: corrupt file, no write permission, no space, unsupported codec → readable message.
- Nothing heavy on the main thread.

## Decisions (mine; the spec leaves them open)

- **Type resolution order:** magic bytes for the formats we act on (PNG, JPEG, GIF, TIFF, HEIC, PDF, ZIP, GZIP, MP4/MOV, TAR) → `URLResourceValues.contentType` → extension. A PNG named `.jpg` is a PNG.
- **ZIP reader is our own** (central directory, stored + DEFLATE via Compression, CRC-32, ZIP64 sizes). Every write is under our control: names with `..`, absolute paths or drive letters are rejected; symlinks are created last and only if they resolve inside the extraction root, so no write can pass through a symlink. `/usr/bin/unzip` gives no such guarantee. Encrypted entries → error.
- **TAR / TAR.GZ:** safe extract into a temp folder, then `/usr/bin/tar -c[z]f` with an argument array.
- **Image tools without a parameter UI:** Rotate = 90° clockwise; Remove Metadata = lossless copy (`CGImageDestinationCopyImageSource`) with EXIF/GPS/IPTC/XMP dropped and orientation kept (re-encode fallback for formats that cannot copy losslessly); Compress = JPEG/HEIC only, quality 0.6, result discarded with a message if not smaller; Resize = small dialog with presets (50 %, 25 %, longest side 2560 / 1920 / 1280 / 800), last choice remembered.
- **Video:** MP4 → MOV passthrough; Mute = composition without audio tracks, passthrough to the same container; M4A = `AVAssetExportPresetAppleM4A`; Snapshot = frame at the middle of the video → PNG.
- **Progress UI:** running tasks with progress and Cancel in the menu bar menu; the menu bar icon shows activity. Notification permission is requested on the first completed task (not at launch); if denied, results still appear, errors use an alert.
- **Float:** compact non-activating shelf panel; rows drag out as real file URLs; ✕ removes from the shelf only; dragging the shelf near the left/right screen edge snaps it there.

## Review Focus

- ZIP entries `../x`, `/abs`, `a/../../x`, a symlink to `/tmp` followed by `link/file` → nothing written outside the root, error reported.
- Cancel mid-export → no output file and no hidden temp file left.
- Read-only destination folder → clear "no permission" error, nothing written.
- Multi-item drops: conversions apply per item; mixed types → only actions applicable to all items are offered.
- Move across volumes: copy fully, then delete the source; a name conflict asks, never overwrites silently.

---

### Task 1: Types, action protocol, registries, output writer, task manager
**Files:** `Citra/Types/FileTypeResolver.swift`, `Citra/Actions/FileAction.swift`, `Citra/Actions/Registries.swift`, `Citra/Actions/OutputWriter.swift` (replaces the PoC parts of `ImageConversion.swift`), `Citra/Tasks/TaskManager.swift`, `Citra/App/AppCoordinator.swift`, menu bar view; tests for resolver, writer, registry applicability.
**Produces:** `struct FileItem { url; type: UTType; isDirectory; isPackage }`, `FileTypeResolver.resolve(_:) -> FileItem`; `protocol FileAction: Sendable { id; title; symbol; func isApplicable(to: [FileItem]) -> Bool; var isAvailable: Bool; func centerText(for: [FileItem]) -> String?; func perform(items: [FileItem], progress: Progress) async throws -> [URL] }`; `Registry.actions(for: MenuMode, items:) -> [any FileAction]`; `OutputWriter.write(nextTo:baseName:extension:_ body: (URL) throws -> Void) throws -> URL`.

### Task 2: Images — conversions (PNG ↔ JPEG ↔ HEIC ↔ TIFF, image → PDF)
### Task 3: Images — tools (Resize, Rotate, Remove Metadata, Compress)
### Task 4: ZIP — safe Extract, Test Integrity
### Task 5: ZIP → TAR / TAR.GZ
### Task 6: Video — MP4 → MOV, Snapshot, Mute, video → M4A
### Task 7: File Actions — AirDrop, Float, Copy, Move, Copy Path, Terminal

Each task: tests first on files generated in the test (real files, real encoders), fail → implement → pass, run the whole suite, commit. Task 8: README, PROGRESS, manual checklist (acceptance A–I) in Russian.
