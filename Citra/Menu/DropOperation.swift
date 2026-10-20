import AppKit

enum DropOperation {
    /// The operation to report back to the drag source. Never `.move` or `.delete`:
    /// a source may remove the original after such a drop.
    static func choose(from mask: NSDragOperation) -> NSDragOperation {
        [NSDragOperation.copy, .generic, .link].first { mask.contains($0) } ?? []
    }
}
