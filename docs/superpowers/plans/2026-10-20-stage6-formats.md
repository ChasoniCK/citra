# Stage 6 — More formats (images, audio, video gaps, subtitles, archives)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use `- [ ]`.

**Goal:** cover the "cheap" rows of the reference format table with system frameworks, the user's ffmpeg and cwebp. Documents, slides, spreadsheets, PDF → office formats and RAR are out of scope (user decision).

**Architecture:** every addition is a `FileAction` in the existing registry; external tools go through `ProcessRunner` with argument arrays and are found in `FFmpeg.searchPaths`; every result goes through `OutputWriter`.

**Spec:** agreed in chat on 2026-10-20 (summary below is the spec).

## Global Constraints
- No new dependencies, nothing bundled. External tools are optional; an action whose tool or encoder is missing is not offered.
- No file reads before the drop: applicability decides by type metadata and file name only.
- Tests only for risky logic (parsers, safety, applicability), per the project's test agreement. Existing suite stays green.
- Ring per file type stays ≤ 9 conversions (no spill into More for a single type).

## Review Focus
- A tar entry with `..` must abort Extract and repack, leaving nothing behind → test in Task 5.
- `x.tar.gz` names its results `x`, never `x.tar` → test in Task 5.
- SRT in Windows-1251 and VTT with BOM/CRLF/no-hours timestamps must convert, not throw → tests in Task 4.
- Audio files must not get video formats, videos must not get the new audio formats → test in Task 3.
- A rotated JPEG must come out upright in WebP (cwebp ignores EXIF orientation) → upright source in Task 2.

---

### Task 1: AVIF, BMP output; SVG input
**Files:** `Citra/Actions/ImageActions.swift`, `CitraTests/ImageConverterTests.swift`
- [ ] `ImageConverter.all` += AVIF (`UTType("public.avif")`, "avif") and BMP (`.bmp`, "bmp"). AVIF uses the HEIC quality setting.
- [ ] `ImageCodec.isReadableImage` also accepts `.svg`. `ImageCodec.source(_:)` falls back for SVG: NSImage drawn into an sRGB `CGContext` (long side ≥ 1024 px, intrinsic size otherwise), returned as a `CGImageSource` over in-memory PNG. `ImageTools.isEditable` stays false for SVG (not encodable).
- [ ] Tests: update the expected id lists; add AVIF/BMP to the round-trip test; `svgConvertsToPNGAt1024` (40×20 red SVG → 1024×512 PNG, red pixel).

### Task 2: WebP via cwebp
**Files:** `Citra/Actions/ImageActions.swift`, `Citra/Settings/SettingsView.swift`, tests in `ImageConverterTests.swift`
- [ ] `struct WebPConverter: FileAction` — id `image.webp`, title `WEBP`, `static let cwebp: URL?` (first executable `cwebp` in `FFmpeg.searchPaths`), available iff found, applicable to readable non-WebP images.
- [ ] Perform: `ImageTools.upright` → temp PNG in `FileManager.temporaryDirectory` (removed in `defer`) → `cwebp -quiet -q <jpegQuality×100> in.png -o <temp>` inside `OutputWriter.write`.
- [ ] Registry: after `ImageConverter.all`, before `ImageToPDF`.
- [ ] Settings → Conversions: one row with cwebp status and `brew install webp` hint.
- [ ] Test (enabled only when cwebp exists): PNG → WebP decodes as `org.webmproject.webp`.

### Task 3: ffmpeg — audio formats, MOV and GIF for ffmpeg-only video
**Files:** `Citra/Actions/FFmpeg.swift`, `Citra/Settings/SettingsView.swift`, `CitraTests/FFmpegTests.swift`
- [ ] Replace `audioOnly` with `input: Input` (`.video`, `.videoOrAudio`, `.audio`) and add `aliases: [String]` (own-format check). MP3 becomes `.videoOrAudio`.
- [ ] New `.audio` formats (all with `-vn`): M4A (`ipod`, aac 256k), WAV (pcm_s16le), FLAC, OGG (`vorbis -strict experimental -ac 2 -q:a 6`, encoder `vorbis`), OPUS (`opus` muxer, libopus 160k), AIFF (pcm_s16be, alias `aif`), WMA (`asf`, wmav2 192k).
- [ ] New `.video` formats: MOV (same args as MP4, muxer `mov`), GIF (`-t VideoToGIF.maxSeconds`, fps/scale/palette filter from `VideoToGIF` constants, `-loop 0`). MP4/MOV/GIF skip AVFoundation-openable videos (they have native actions).
- [ ] Settings section title no longer lists formats.
- [ ] Test `inputKindsDoNotMix`: `.mp3` → audio targets without MP3 and without MKV/MOV/GIF; `.mkv` → video targets + MP3, no WAV; `.aif` gets no AIFF. Uses `FFmpegConverter.isApplicable` directly (independent of the installed ffmpeg).

### Task 4: Subtitles
**Files:** create `Citra/Actions/Subtitles.swift`, `CitraTests/SubtitleTests.swift`
- [ ] `enum Subtitles` with `struct Cue { start: Int; end: Int; lines: [String] }` (ms), `static func parse(_ text: String) -> [Cue]`, `static func srt(_:) / vtt(_:) / plainText(_:) -> String`, `static func decode(_ data: Data) -> String` (UTF-8 with BOM stripped, else Foundation's encoding detection, else Latin-1).
- [ ] Parse: normalize CRLF/CR, split on blank lines, a block is a cue iff it has a `-->` line; timestamps `[h:]mm:ss[.,]fff`, cue settings ignored; WEBVTT header, NOTE/STYLE/REGION blocks skipped.
- [ ] Output: SRT renumbers from 1, `HH:MM:SS,mmm`; VTT `WEBVTT` header, `HH:MM:SS.mmm`, `&`/`<` escaped; both keep only `<i> <b> <u>` tags and drop `{\…}` overrides; TXT has no tags, decoded entities, consecutive duplicate lines removed.
- [ ] `struct SubtitleConverter: FileAction` — ids `subtitles.srt|vtt|txt`, input by extension `srt`/`vtt`, not own format; throws a clear error when no cues found. Registry: conversion mode.
- [ ] Tests: SRT→VTT exact text; VTT (BOM, CRLF, `mm:ss.fff`, settings, NOTE, `<v>`/`<c>` tags, entities) → SRT exact text; YouTube-style rolling VTT → TXT deduped; cp1251 bytes decode to Cyrillic.

### Task 5: Archives — TAR, TAR.GZ, plain GZ
**Files:** `Citra/Actions/Repack.swift`, `Citra/Actions/Zip.swift`, `Citra/Settings/SettingsView.swift`, `CitraTests/RepackTests.swift`, `CitraTests/ZipTests.swift`
- [ ] `enum ArchiveKind { zip, tar, tarGz }` with `static func of(_ item: FileItem) -> ArchiveKind?` (zip by `type == .zip`; tar by `.tar` extension or tar type; tarGz by `.tar.gz`/`.tgz` name) and `baseName(_ url:)` (`x.tar.gz` → `x`).
- [ ] `RepackArchive(target:)` — ids `archive.zip|tar|targz`, applicable to any other kind. Staging: ZIP via `ZipExtractor` (unchanged), TAR/TAR.GZ via `/usr/bin/tar -xf` (refuses `..`, strips `/`, no writes through symlinks). Pack: `tar -c` + `-z` / `--format zip`.
- [ ] Extract (`archive.extract`) also takes TAR/TAR.GZ (single top folder detected from `tar -tf`, then `--strip-components 1`) and plain `.gz` (copy beside temp, `gzip -d`, copy removed in `defer`). Test stays ZIP-only (`archive.test`). Rename `zip.*` ids to `archive.*`; Settings group "Archives".
- [ ] Tests: TAR → ZIP keeps tree; TAR.GZ offers ZIP+TAR, names `x.zip`; Extract of tar with `../a.txt` throws and leaves only the archive; plain `log.txt.gz` extracts to `log.txt`.

### Task 6: Docs and verification
- [ ] README table + availability notes; PROGRESS.md Stage 6 section.
- [ ] Full test suite, Release build without warnings; one manual drag in Finder for a new type.
