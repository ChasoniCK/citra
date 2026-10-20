# Stage 4 — Settings and System Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menu bar with Enable / Settings… / Quit, and a SwiftUI Settings window whose values actually drive the app.

**Spec:** `PROMPT.md` `<settings>`. **Tests:** only risky logic (agreed with the user): modifier mapping and output location.

## Decisions (mine)

- **All five tabs now**, each minimal: every function they configure already exists after Stage 3. FFmpeg status moves to Stage 5 together with the FFmpeg converters, so the UI never advertises formats that do not exist yet.
- **Storage:** `UserDefaults` behind one `AppSettings` (keys, registered defaults, typed reads usable off the main thread); SwiftUI binds the same keys with `@AppStorage`.
- **Shortcuts:** each mode gets one of ⌘ ⇧ ⌃ ⌥. Picking a modifier already used by another mode swaps the two, so a duplicate can never exist. Several held → fixed priority by modifier ⌘ > ⇧ > ⌃ > ⌥.
- **Appearance:** size Small / Normal / Large (0.85 / 1 / 1.15), animation Off / Fast / Normal, accent presets (orange from the references, blue, purple, pink, green, graphite).
- **Conversions:** JPEG and HEIC quality; video: "passthrough when possible" or "always re-encode"; list of conversions per file type with availability.
- **File Actions:** terminal Terminal / iTerm2 (iTerm2 only when installed); shelf edge left / right.
- **General:** Enable, Launch at Login (`SMAppService.mainApp`, shows "needs approval" with a link to Login Items), notifications on/off with system status, results next to the original or in a chosen folder.
- **Tests stay isolated from the user's settings:** the test scheme passes launch arguments that pin output location, video quality and size.

## Tasks

1. `AppSettings` + `MenuMode.resolve(flags, mapping)` + swap rule (tests: priority, custom mapping, swap) + output location (test).
2. Wire: DragMonitor (enabled, mapping), ring (size, motion, accent), ImageCodec quality, video preset, OutputWriter destination, Notifier toggle, Terminal app, shelf edge.
3. Settings window, menu bar (Enable / Settings… / tasks / Quit), Launch at Login.
4. Build, short Russian checklist, PROGRESS/README, commit.
