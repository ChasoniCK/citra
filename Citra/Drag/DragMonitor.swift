import AppKit
import Carbon.HIToolbox

/// Detects file drags started in any app and reports the modifier-selected mode while the
/// button is held. Only a global mouse-down monitor plus polling of public state
/// (`pressedMouseButtons`, `modifierFlags`, drag pasteboard `changeCount`): no
/// Accessibility or Input Monitoring permission is involved.
@MainActor
final class DragMonitor {
    /// A file drag started; URLs read from the drag pasteboard before any drop.
    var onBegin: ([URL]) -> Void = { _ in }
    /// The resolved mode changed during the drag (nil = no relevant modifier held).
    var onModeChange: (MenuMode?) -> Void = { _ in }
    /// The mouse button was released or the session was cancelled.
    var onEnd: () -> Void = {}

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var changeCountAtMouseDown = 0
    private var monitors: [Any] = []
    private var timer: Timer?
    private var inSession = false
    private var suppressed = false
    private var mode: MenuMode?
    private var sessionStart = Date.distantPast

    // Diagnostics answering the feasibility questions.
    private var draggedEventsDuringSession = 0
    private var sawGlobalMouseUpDuringSession = false
    private var sawEscapeKeyState = false

    #if DEBUG
    /// `-CitraDebugMode tools` pins a mode so an automated drag without modifiers can reach the panel.
    private let debugMode = UserDefaults.standard.string(forKey: "CitraDebugMode").flatMap(MenuMode.init(rawValue:))
    #endif

    func start() {
        addMonitor(.leftMouseDown) { $0.mouseDown() }
        addMonitor(.leftMouseDragged) { if $0.inSession { $0.draggedEventsDuringSession += 1 } }
        addMonitor(.leftMouseUp) { if $0.inSession { $0.sawGlobalMouseUpDuringSession = true } }
    }

    /// Hides the ring for the rest of this drag, e.g. after the drag was cancelled over it.
    func suppressUntilMouseUp() {
        guard inSession else { return }
        suppressed = true
        if mode != nil { mode = nil; onModeChange(nil) }
    }

    private func addMonitor(_ mask: NSEvent.EventTypeMask, _ body: @escaping @MainActor (DragMonitor) -> Void) {
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { if let self { body(self) } }
        }
        if let monitor { monitors.append(monitor) } else { PocLog.write("global monitor \(mask) unavailable") }
    }

    private func mouseDown() {
        changeCountAtMouseDown = dragPasteboard.changeCount
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return finish() }

        if !inSession {
            let count = dragPasteboard.changeCount
            guard count != changeCountAtMouseDown else { return }
            changeCountAtMouseDown = count // one look per drag
            let urls = dragPasteboard.readObjects(forClasses: [NSURL.self],
                                                  options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            guard !urls.isEmpty else {
                PocLog.write("drag without file URLs, types=\(dragPasteboard.types?.map(\.rawValue) ?? [])")
                return
            }
            inSession = true
            sessionStart = .now
            draggedEventsDuringSession = 0
            sawGlobalMouseUpDuringSession = false
            sawEscapeKeyState = false
            PocLog.write("session begin: \(urls.count) item(s) \(urls.map(\.lastPathComponent)) flags=\(Self.describe(NSEvent.modifierFlags))")
            onBegin(urls)
        }

        // Experiment: is the Escape key state readable without Input Monitoring?
        if !sawEscapeKeyState, CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Escape)) {
            sawEscapeKeyState = true
            PocLog.write("Escape key state observed during drag")
        }

        guard !suppressed else { return }
        var newMode = MenuMode.resolve(NSEvent.modifierFlags)
        #if DEBUG
        newMode = debugMode ?? newMode
        #endif
        if newMode != mode {
            PocLog.write("mode \(mode.map { "\($0)" } ?? "none") → \(newMode.map { "\($0)" } ?? "none") at +\(ms(since: sessionStart))ms flags=\(Self.describe(NSEvent.modifierFlags))")
            mode = newMode
            onModeChange(newMode)
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        guard inSession else { return }
        PocLog.write("session end after \(ms(since: sessionStart))ms: global leftMouseDragged seen=\(draggedEventsDuringSession), global leftMouseUp seen=\(sawGlobalMouseUpDuringSession)")
        inSession = false
        suppressed = false
        mode = nil
        onEnd()
    }

    static func describe(_ flags: NSEvent.ModifierFlags) -> String {
        let names: [(NSEvent.ModifierFlags, String)] = [(.command, "⌘"), (.shift, "⇧"), (.control, "⌃"), (.option, "⌥")]
        let s = names.filter { flags.contains($0.0) }.map(\.1).joined()
        return s.isEmpty ? "-" : s
    }
}

func ms(since date: Date) -> Int { Int(Date.now.timeIntervalSince(date) * 1000) }
