import Foundation
import Testing
@testable import Citra

struct FileNamingTests {
    let dir = URL(filePath: "/tmp/citra-naming", directoryHint: .isDirectory)

    func unique(ext: String = "jpg", taken: Set<String>) -> String {
        FileNaming.uniqueURL(directory: dir, baseName: "photo", pathExtension: ext) {
            taken.contains($0.lastPathComponent)
        }.lastPathComponent
    }

    @Test func usesPlainNameWhenFree() {
        #expect(unique(taken: []) == "photo.jpg")
    }

    @Test func appendsTwoOnFirstCollision() {
        #expect(unique(taken: ["photo.jpg"]) == "photo 2.jpg")
    }

    @Test func skipsAllTakenNumbers() {
        #expect(unique(taken: ["photo.jpg", "photo 2.jpg", "photo 3.jpg"]) == "photo 4.jpg")
    }

    @Test func supportsNoExtension() {
        #expect(unique(ext: "", taken: ["photo"]) == "photo 2")
    }

    @Test func staysInDirectory() {
        let url = FileNaming.uniqueURL(directory: dir, baseName: "photo", pathExtension: "jpg") { _ in false }
        #expect(url.deletingLastPathComponent().path == dir.path)
    }
}
