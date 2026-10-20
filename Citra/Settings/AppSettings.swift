import AppKit

enum ModifierKey: String, CaseIterable, Sendable {
    case command, shift, control, option

    /// When several are held, the first in this order decides (spec: ⌘ > ⇧ > ⌃).
    static let priority: [ModifierKey] = [.command, .shift, .control, .option]

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .shift: .shift
        case .control: .control
        case .option: .option
        }
    }

    var label: String {
        switch self {
        case .command: "⌘ Command"
        case .shift: "⇧ Shift"
        case .control: "⌃ Control"
        case .option: "⌥ Option"
        }
    }
}

/// Which modifier opens which ring. Two modes never share a modifier.
struct ModifierMapping: Equatable, Sendable {
    var conversion = ModifierKey.command
    var tools = ModifierKey.shift
    var fileActions = ModifierKey.control

    subscript(mode: MenuMode) -> ModifierKey {
        get {
            switch mode {
            case .conversion: conversion
            case .tools: tools
            case .fileActions: fileActions
            }
        }
        set {
            switch mode {
            case .conversion: conversion = newValue
            case .tools: tools = newValue
            case .fileActions: fileActions = newValue
            }
        }
    }

    func mode(for key: ModifierKey) -> MenuMode? { MenuMode.allCases.first { self[$0] == key } }

    /// Gives `key` to `mode`; a mode that already had `key` takes `mode`'s previous one (a swap).
    func assigning(_ key: ModifierKey, to mode: MenuMode) -> ModifierMapping {
        var next = self
        if let other = self.mode(for: key), other != mode { next[other] = self[mode] }
        next[mode] = key
        return next
    }
}

enum OutputLocation: String, CaseIterable, Sendable { case original, folder }
enum RingSize: String, CaseIterable, Sendable {
    case small, normal, large

    var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .normal: 1
        case .large: 1.15
        }
    }
}
enum Motion: String, CaseIterable, Sendable { case off, fast, normal }
enum Accent: String, CaseIterable, Sendable { case orange, blue, purple, pink, green, graphite }
enum VideoQuality: String, CaseIterable, Sendable { case passthrough, reencode }
enum TerminalChoice: String, CaseIterable, Sendable { case terminal, iterm }
enum ShelfEdge: String, CaseIterable, Sendable { case left, right }

/// Every setting in one place: `UserDefaults` keys with registered defaults, typed reads that are safe
/// off the main thread. SwiftUI binds the same keys with `@AppStorage`.
enum AppSettings {
    enum Key {
        static let enabled = "enabled"
        static let notifications = "notifications"
        static let outputLocation = "outputLocation"
        static let outputFolder = "outputFolder"
        static let ringSize = "ringSize"
        static let motion = "motion"
        static let accent = "accent"
        static let jpegQuality = "jpegQuality"
        static let heicQuality = "heicQuality"
        static let videoQuality = "videoQuality"
        static let terminal = "terminal"
        static let shelfEdge = "shelfEdge"
        static func modifier(_ mode: MenuMode) -> String { "modifier.\(mode)" }
    }

    static func registerDefaults() {
        let base = ModifierMapping()
        var values: [String: Any] = [
            Key.enabled: true, Key.notifications: true, Key.outputLocation: OutputLocation.original.rawValue,
            Key.ringSize: RingSize.normal.rawValue, Key.motion: Motion.normal.rawValue, Key.accent: Accent.orange.rawValue,
            Key.jpegQuality: 0.9, Key.heicQuality: 0.8, Key.videoQuality: VideoQuality.passthrough.rawValue,
            Key.terminal: TerminalChoice.terminal.rawValue, Key.shelfEdge: ShelfEdge.right.rawValue,
        ]
        for mode in MenuMode.allCases { values[Key.modifier(mode)] = base[mode].rawValue }
        UserDefaults.standard.register(defaults: values)
    }

    private static var defaults: UserDefaults { .standard }
    private static func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    static var isEnabled: Bool { defaults.object(forKey: Key.enabled) as? Bool ?? true }
    static var notificationsEnabled: Bool { defaults.object(forKey: Key.notifications) as? Bool ?? true }
    static var outputLocation: OutputLocation { value(Key.outputLocation, .original) }
    static var outputFolder: URL? {
        defaults.string(forKey: Key.outputFolder).flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
    }
    static var ringSize: RingSize { value(Key.ringSize, .normal) }
    static var motion: Motion { value(Key.motion, .normal) }
    static var accent: Accent { value(Key.accent, .orange) }
    static var jpegQuality: Double { defaults.object(forKey: Key.jpegQuality) as? Double ?? 0.9 }
    static var heicQuality: Double { defaults.object(forKey: Key.heicQuality) as? Double ?? 0.8 }
    static var videoQuality: VideoQuality { value(Key.videoQuality, .passthrough) }
    static var terminal: TerminalChoice { value(Key.terminal, .terminal) }
    static var shelfEdge: ShelfEdge { value(Key.shelfEdge, .right) }

    static var mapping: ModifierMapping {
        var m = ModifierMapping()
        for mode in MenuMode.allCases { m[mode] = value(Key.modifier(mode), m[mode]) }
        return m
    }

    static func setMapping(_ m: ModifierMapping) {
        for mode in MenuMode.allCases { defaults.set(m[mode].rawValue, forKey: Key.modifier(mode)) }
    }
}
