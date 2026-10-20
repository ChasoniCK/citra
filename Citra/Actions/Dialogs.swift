import AppKit

/// A small choice dialog for tools that need one parameter (Resize, Speed, Crop).
@MainActor
enum PresetDialog {
    /// Index of the chosen option, or nil when cancelled. The last choice per `key` is preselected.
    static func choose(title: String, message: String, options: [String], confirm: String, rememberAs key: String) -> Int? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        popup.addItems(withTitles: options)
        popup.selectItem(at: min(UserDefaults.standard.integer(forKey: key), options.count - 1))
        alert.accessoryView = popup
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        UserDefaults.standard.set(popup.indexOfSelectedItem, forKey: key)
        return popup.indexOfSelectedItem
    }
}

/// "1:05.5" ⇄ 65.5 seconds; also accepts plain seconds and h:mm:ss.
enum TimeText {
    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (i, part) in parts.enumerated() {
            guard let value = Double(part), value >= 0, i == parts.count - 1 || value == value.rounded() else { return nil }
            if i > 0, value >= 60 { return nil }
            total = total * 60 + value
        }
        return total
    }

    static func string(_ seconds: Double) -> String {
        let whole = Int(seconds), tenths = Int(((seconds - Double(whole)) * 10).rounded())
        let base = whole >= 3600 ? String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
                                 : String(format: "%d:%02d", whole / 60, whole % 60)
        return tenths == 0 ? base : "\(base).\(min(tenths, 9))"
    }
}

@MainActor
enum TrimDialog {
    /// The kept range in seconds, or nil when cancelled.
    static func ask(duration: Double, name: String) -> ClosedRange<Double>? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Trim “\(name)”"
        alert.informativeText = "Keep from Start to End (m:ss or seconds). Length \(TimeText.string(duration)). The cut snaps to the nearest keyframe."
        let start = NSTextField(string: TimeText.string(0)), end = NSTextField(string: TimeText.string(duration))
        let grid = NSGridView(views: [[NSTextField(labelWithString: "Start"), start], [NSTextField(labelWithString: "End"), end]])
        grid.column(at: 1).width = 120
        grid.frame = NSRect(x: 0, y: 0, width: 200, height: 56)
        alert.accessoryView = grid
        alert.addButton(withTitle: "Trim")
        alert.addButton(withTitle: "Cancel")
        while alert.runModal() == .alertFirstButtonReturn {
            if let a = TimeText.seconds(start.stringValue), let b = TimeText.seconds(end.stringValue), a < b, b <= duration + 0.05 {
                return a...min(b, duration)
            }
            alert.informativeText = "Start must be before End, both within \(TimeText.string(duration))."
        }
        return nil
    }
}
