import Foundation

enum Workspace {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Packager/Workspace", isDirectory: true)
    }()

    @discardableResult
    static func ensure() -> URL {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func cleanAll() {
        try? FileManager.default.removeItem(at: root)
        ensure()
    }
}
