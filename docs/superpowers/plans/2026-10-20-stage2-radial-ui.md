# Stage 2 — Radial UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the PoC ring with one reusable radial menu that matches the references for 1…N sectors in all three modes, with hover, appear, mode-switch and completion animations, and an overflow ring for more than 10 actions.

**Architecture:** Geometry stays pure (`RadialLayout`, new `OverflowLayout`, shared rounded annular-sector path). `RadialMenuModel` owns what is shown and the hit-test that decides primary / overflow / nothing. SwiftUI draws; AppKit supplies the behind-window blur (`NSVisualEffectView`, `state = .active` because the app is never active) masked to the ring. Rendering is checked by `ImageRenderer` PNGs compared against the references.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, XcodeGen.

**Context:** Stage 1 lessons in `docs/feasibility.md`.

## Global Constraints

- Geometry from the references (2x screenshots, measured with brightness profiles): disc radius 136 pt, sector outer 129.5, sector inner 53.5, transparent hole 46, gap 5, outer corner radius 14, inner corner radius 8, center pill 84×39 (grows up to 100 for longer text).
- Colors (dark): disc ≈ `#272526` translucent over blur, sector ≈ white 9 % (`#2E2E2E` on the disc) with a lighter outer edge, hovered = accent gradient `#FA7349` → `#D44F02` (accent default orange), labels white, uppercase, bold, tracked.
- Light and dark appearance; the hole is tinted (not alpha 0) so the whole disc stays a drop target and releasing in the center cancels.
- Redraw on cursor movement only when the hovered target changes.
- No new dependencies; no Liquid Glass (references are a dark frosted HUD; glass would diverge from them).

## Decision: more than 10 actions

More than 10 → the ring shows the first 9 plus a **More** sector; hovering More opens an **outer arc** (r 142…200, 28° per item) centred on More, and the user keeps moving outward to pick. Chosen over "top-N + order in settings" because every working action stays reachable during the same drag gesture, and overflow is rare (mainly FFmpeg video formats), so the bigger window appears only then. Dropping on More itself does nothing.

## Review Focus

- 1 and 2 sectors with rounded corners: seam at the bottom / horizontal seams, no NaN or inverted arcs.
- 10 sectors: inner corners clamped so the inner arc never inverts.
- Overflow ring hit-testable only while More or an overflow item is hovered; More is not a drop target.
- Mode switch while hovering: hovered index never points past the new item count.
- Dismiss animation must not leave the panel intercepting a new drag (new session orders it out at once).

---

### Task 1: Rounded sector geometry
**Files:** `Citra/Menu/RadialLayout.swift`, `CitraTests/RadialLayoutTests.swift`
**Produces:** `func annularSectorPath(from: Double, to: Double, inner: CGFloat, outer: CGFloat, gap: CGFloat, outerCorner: CGFloat, innerCorner: CGFloat) -> CGPath` (angles clockwise from 12 o'clock, y-up); `RadialLayout` gains `outerCornerRadius`, `innerCornerRadius` (default 0) and `labelWidth: CGFloat` (chord at mid radius minus padding).
- [ ] Tests: rounded path excludes the sharp outer corner point that the unrounded path contains; mid-sector point contained; bounding box within outer radius; n = 1 keeps the bottom seam; n = 10 path is finite and non-empty. Fail → implement exact fillets (fillet centre at distance `R−ρ` / `r+ρ` from centre and `gap/2+ρ` from the seam ray; clamp ρ until the arc spans stay positive) → pass.

### Task 2: Overflow geometry and model hit-test
**Files:** `Citra/Menu/OverflowLayout.swift`, `Citra/Menu/RadialMenuView.swift` (model part), `CitraTests/RadialMenuModelTests.swift`
**Produces:** `struct OverflowLayout { anchorAngle, count, innerRadius, outerRadius, itemAngle, gap; hitTest(_:) -> Int?; sectorPath(_:); labelPoint(of:) }`; `enum RingTarget: Equatable { case primary(Int), overflow(Int) }`; model: `primaryItems`, `overflowItems`, `hovered: RingTarget?`, `func target(at p: CGPoint) -> RingTarget?`, `func item(for: RingTarget) -> RadialMenuItem?` (nil for More).
- [ ] Tests: ≤10 items → no More; 12 items → 10 primary, last is More, 3 overflow; overflow hit only after More hovered; More not actionable. Fail → implement → pass.

### Task 3: Ring view and backdrop
**Files:** `Citra/Menu/RadialMenuView.swift`, `Citra/Menu/RingBackdrop.swift`, `Citra/Menu/RadialMenuPanelController.swift`, `CitraTests/RingRenderTests.swift`
- [ ] Render test writes PNGs (dark/light; 1, 2, 6, 9, 12 items; idle/hovered) to a temp folder and asserts non-empty images. Compare against the references by eye, iterate.
- [ ] Backdrop: `NSVisualEffectView` (`.hudWindow` dark, `.popover` light, `.behindWindow`, `.active`) masked to the annulus 46…136; panel resizes when overflow exists.

### Task 4: Animations and completion
**Files:** model, view, panel controller, `AppCoordinator.swift`
- [ ] Appear: scale 0.86 → 1 + opacity, spring ~0.22 s. Mode switch: sector group keyed by a generation id, cross-fade + scale. Hover: fill + 4 pt push-out. Completion: dropped sector flashes, ring fades/scales out over ~0.2 s, then `orderOut`; a new drag session orders it out immediately.
- [ ] Center text: idle = size / "N items" / "Folder"; hovered = item `detail` ("PNG → JPEG") or title.
- [ ] Existing panel tests keep passing; add: drop on More refused, drop on overflow item after hovering More accepted.

### Task 5: Verify and record
- [ ] Clean build + tests, Release build; `PROGRESS.md`, `README.md`; commit; manual checklist in Russian (includes "ring appears without mouse movement").
