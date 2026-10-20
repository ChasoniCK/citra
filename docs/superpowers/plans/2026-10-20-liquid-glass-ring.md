# Liquid Glass Ring Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The ring's sectors and center pill drawn with the system Liquid Glass material; everything else about the ring unchanged.

**Architecture:** SwiftUI `glassEffect(.regular, in:)` on each sector (inside one `GlassEffectContainer`) and on the center pill. The AppKit behind-window blur (`RingBackdrop`) goes away. Hover/confirm highlight is our own accent fill on top of the glass.

**Tech Stack:** SwiftUI (macOS 26 Glass API), AppKit panel.

**Spec:** approved in chat on 2026-10-20 (variant A of the spike: every sector its own piece of glass).

## Global Constraints

- Minimum macOS 26.0 (`project.yml`, `Info.plist` `LSMinimumSystemVersion`, README «Требования»).
- No disc under the sectors; a near-invisible fill stays in the gaps and under the overflow arc so drops there do not fall through to the window below.
- `Glass.tint` is not used: in a never-active app it renders gray (seen in the spike, also in a standalone test app).
- Tests: risky logic only — this is appearance; existing suite must stay green.

## Spike findings the builder needs

- `GlassEffectContainer` lays its content out vertically: wrap the `ForEach` in a `ZStack`.
- Activating the app, making the panel key, `appearsActive`, `_setForceActiveControls:` and `_setHasActiveAppearance:` all leave the glass tint gray.

## Review Focus

- Drop on the gap between two sectors → no action runs and the drop does not land in the Finder window under the ring.
- Drop in the center hole → cancels, as before.
- Light appearance → labels readable on glass.
- Ring fade-in/out → glass fades with the rest of the ring, no glass left on screen after the ring is gone.
- Overflow arc (more than 10 items) → glass sectors, gaps still a drop target.

---

### Task 1: Glass ring

**Files:**
- Modify: `Citra/Menu/RadialMenuView.swift` (palette, `Disc`, `SectorView`, `OverflowArcView`, `CenterPill`)
- Modify: `Citra/Menu/RadialMenuPanelController.swift` (remove backdrop and its fade)
- Delete: `Citra/Menu/RingBackdrop.swift` (regenerate the project with `xcodegen generate`)
- Modify: `project.yml`, `Citra/Info.plist`, `README.md`, `CitraTests/RingRenderTests.swift` (comment: glass does not render in `ImageRenderer`)

- [ ] **Step 1:** `RingPalette` keeps only `backing` (gap fill), `hole`, `holeEdge`, `label`, accent top/bottom.
- [ ] **Step 2:** `SectorView` = label + accent fill (opacity 1 when hovered or confirmed, brightness +0.12 when confirmed) + `.glassEffect(.regular, in: shape)` + the existing push-out offset and spring.
- [ ] **Step 3:** `CenterPill` background → `.glassEffect(.regular, in: Capsule())`; overflow band fill → `palette.backing`, no stroke, no shadow.
- [ ] **Step 4:** Remove the spike's `GlassSpike` switch and preview launch hook once verification is done.
- [ ] **Step 5:** Run `xcodebuild -project Citra.xcodeproj -scheme Citra -destination 'platform=macOS' test` — expected: all tests pass.

### Task 2: Verification on screen

- [ ] Dark and light screenshots: idle, hover, overflow.
- [ ] Glass under a parent `.opacity` fades (standalone check).
- [ ] Real drag from Finder: drop on a sector runs it; drop on a gap and in the hole does nothing and does not reach Finder.
