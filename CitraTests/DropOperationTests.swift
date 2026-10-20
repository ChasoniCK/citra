import AppKit
import Testing
@testable import Citra

struct DropOperationTests {
    @Test func prefersNonDestructiveOperation() {
        let cases: [(NSDragOperation, NSDragOperation)] = [
            (.every, .copy),
            ([.copy, .move], .copy),
            (.generic, .generic),
            ([.generic, .link], .generic),
            (.link, .link),
            // Never claim a move or delete: the source could remove the original.
            (.move, []),
            (.delete, []),
            ([], []),
        ]
        for (mask, expected) in cases {
            #expect(DropOperation.choose(from: mask) == expected, "mask \(mask.rawValue)")
        }
    }
}
