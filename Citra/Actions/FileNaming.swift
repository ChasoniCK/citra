import Foundation

enum FileNaming {
    /// Finder-style free name: `photo.jpg`, then `photo 2.jpg`, `photo 3.jpg`, …
    static func uniqueURL(directory: URL, baseName: String, pathExtension: String,
                          exists: (URL) -> Bool) -> URL {
        func candidate(_ n: Int) -> URL {
            let name = n == 1 ? baseName : "\(baseName) \(n)"
            return directory.appending(path: pathExtension.isEmpty ? name : "\(name).\(pathExtension)")
        }
        var n = 1
        while exists(candidate(n)) { n += 1 }
        return candidate(n)
    }
}
