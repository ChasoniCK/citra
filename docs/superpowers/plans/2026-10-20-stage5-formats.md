# Stage 5 — More Formats and Tools Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The formats and tools the spec lists for Stage 5, each registered through `Registry` only.
**Spec:** `PROMPT.md` `<plan>` Stage 5, `<file_processing>` (FFmpeg, GIF). **Tests:** risky logic only.

## Scope (mine, from the spec's list)

| What | How | Mode |
|---|---|---|
| MKV (stream copy), WebM (VP9/Opus), AVI (MPEG-4/MP3), WMV (WMV2/WMA2), MP3 (audio) | external `ffmpeg`, argument array, progress from `-progress pipe:1`, duration from `ffprobe` | ⌘ |
| MP4 for files AVFoundation cannot open (MKV, AVI, WebM, WMV…) | `ffmpeg` H.264/AAC | ⌘ |
| MOV → MP4 | AVFoundation passthrough (counterpart of MP4 → MOV) | ⌘ |
| GIF from video | AVAssetImageGenerator + ImageIO, 10 fps, ≤ 480 px, first 15 s | ⌘ |
| Compress video | AVFoundation 720p export, discarded if not smaller | ⇧ |
| Trim | dialog with start/end; passthrough export of the range | ⇧ |
| Speed | presets 0.5× / 1.5× / 2× / 4×; time-scaled composition, pitch kept | ⇧ |
| Crop | centered presets 1:1 / 16:9 / 9:16 / 4:3; video composition | ⇧ |
| PDF Merge (2+ PDFs) / Split (one PDF per page into a folder) | PDFKit | ⇧ |

- Each FFmpeg format is available only when `ffmpeg` is in `/opt/homebrew/bin` or `/usr/local/bin` **and** has the encoders it needs (`ffmpeg -encoders`, read once at launch). Settings → Conversions shows the status and `brew install ffmpeg`.
- No file is read before the drop (folder-access prompts): PDF page counts and the like are checked when the action runs.

## Tests
FFmpeg progress parsing and argument array (paths stay single arguments), Trim time parsing, PDF merge order and split page count.
