import AppKit

/// Which ring to show, chosen by the modifier held during the drag.
enum MenuMode: Sendable {
    case conversion, tools, fileActions

    /// Fixed priority when several are held: ⌘ > ⇧ > ⌃. Other modifiers are ignored.
    static func resolve(_ flags: NSEvent.ModifierFlags) -> MenuMode? {
        if flags.contains(.command) { return .conversion }
        if flags.contains(.shift) { return .tools }
        if flags.contains(.control) { return .fileActions }
        return nil
    }
}
