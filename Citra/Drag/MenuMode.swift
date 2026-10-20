import AppKit

/// Which ring to show, chosen by the modifier held during the drag.
enum MenuMode: CaseIterable, Sendable {
    case conversion, tools, fileActions

    var title: String {
        switch self {
        case .conversion: "Conversion"
        case .tools: "Tools"
        case .fileActions: "File Actions"
        }
    }

    /// Default mapping (⌘ conversion, ⇧ tools, ⌃ file actions), fixed priority ⌘ > ⇧ > ⌃.
    static func resolve(_ flags: NSEvent.ModifierFlags) -> MenuMode? { resolve(flags, mapping: ModifierMapping()) }

    /// With a user mapping: the first held modifier in ⌘ > ⇧ > ⌃ > ⌥ order that opens a ring decides.
    static func resolve(_ flags: NSEvent.ModifierFlags, mapping: ModifierMapping) -> MenuMode? {
        ModifierKey.priority.lazy.filter { flags.contains($0.flag) }.compactMap(mapping.mode(for:)).first
    }
}
