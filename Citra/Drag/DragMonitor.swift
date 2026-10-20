import AppKit
import Carbon.HIToolbox

/// Detects file drags started in any app and reports the modifier-selected mode while the
/// button is held. Only a global mouse-down monitor plus polling of public state
/// (`pressedMouseButtons`, `modifierFlags`, drag pasteboard `changeCount`, Escape key state):
/// no Accessibility or Input Monitoring permission is involved (docs/feasibility.md).
@MainActor
final class DragMonitor {
    /// A file drag started; URLs read from the drag pasteboard before any drop.
    var onBegin: ([URL]) -> Void = { _ in }
    /// The resolved mode changed during the drag (nil = no relevant modifier held, or Escape).
    var onModeChange: (MenuMode?) -> Void = { _ in }
    /// The mouse button was released.
    var onEnd: () -> Void = {}

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var changeCountAtMouseDown = 0
    private var monitor: Any?
    private var timer: Timer?
    private var inSession = false
    private var suppressed = false
    private var mode: MenuMode?
    private var mapping = ModifierMapping()

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        if monitor == nil { PocLog.write("global mouse-down monitor unavailable") }
    }

    private func mouseDown() {
        guard AppSettings.isEnabled else { return }
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
            guard !urls.isEmpty else { return }
            inSession = true
            mapping = AppSettings.mapping
            PocLog.write("session begin: \(urls.count) item(s)")
            onBegin(urls)
        }

        // Escape cancels the drag in the source app; hide the ring until the button is released.
        if !suppressed, CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Escape)) {
            suppressed = true
            PocLog.write("Escape: ring suppressed until mouse up")
        }

        let newMode = suppressed ? nil : MenuMode.resolve(NSEvent.modifierFlags, mapping: mapping)
        if newMode != mode {
            mode = newMode
            onModeChange(newMode)
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        guard inSession else { return }
        PocLog.write("session end")
        inSession = false
        suppressed = false
        mode = nil
        onEnd()
    }
}
