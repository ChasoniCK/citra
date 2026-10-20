import AppKit
import Testing
@testable import Citra

struct SettingsTests {
    @Test func defaultMappingKeepsSpecPriority() {
        let m = ModifierMapping()
        #expect(MenuMode.resolve([.command, .shift, .control], mapping: m) == .conversion)
        #expect(MenuMode.resolve([.shift, .control], mapping: m) == .tools)
        #expect(MenuMode.resolve(.option, mapping: m) == nil)
    }

    @Test func customMappingFollowsTheHeldModifier() {
        let m = ModifierMapping(conversion: .option, tools: .command, fileActions: .shift)
        #expect(MenuMode.resolve(.option, mapping: m) == .conversion)
        #expect(MenuMode.resolve([.command, .option], mapping: m) == .tools) // ⌘ outranks ⌥
        #expect(MenuMode.resolve(.control, mapping: m) == nil)
        #expect(MenuMode.resolve([.control, .shift], mapping: m) == .fileActions) // unassigned ⌃ is skipped
    }

    /// Two modes can never share a modifier: taking one that is in use swaps it.
    @Test func assigningAUsedModifierSwaps() {
        let m = ModifierMapping().assigning(.shift, to: .conversion)
        #expect(m == ModifierMapping(conversion: .shift, tools: .command, fileActions: .control))
        let n = ModifierMapping().assigning(.option, to: .tools)
        #expect(n == ModifierMapping(conversion: .command, tools: .option, fileActions: .control))
    }

    @Test func outputGoesNextToTheOriginalOrIntoTheChosenFolder() {
        let src = URL(filePath: "/tmp/a/photo.png"), chosen = URL(filePath: "/tmp/out", directoryHint: .isDirectory)
        #expect(OutputWriter.destination(for: src, location: .original, folder: chosen).path == "/tmp/a")
        #expect(OutputWriter.destination(for: src, location: .folder, folder: chosen).path == "/tmp/out")
        #expect(OutputWriter.destination(for: src, location: .folder, folder: nil).path == "/tmp/a")
    }
}
