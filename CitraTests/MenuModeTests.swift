import AppKit
import Testing
@testable import Citra

struct MenuModeTests {
    @Test func resolvesWithPriorityCommandShiftControl() {
        let cases: [(NSEvent.ModifierFlags, MenuMode?)] = [
            (.command, .conversion),
            (.shift, .tools),
            (.control, .fileActions),
            ([.command, .shift, .control], .conversion),
            ([.shift, .control], .tools),
            ([.command, .option], .conversion),
            ([.capsLock, .control], .fileActions),
            (.option, nil),
            ([], nil),
        ]
        for (flags, expected) in cases {
            #expect(MenuMode.resolve(flags) == expected, "flags \(flags.rawValue)")
        }
    }
}
