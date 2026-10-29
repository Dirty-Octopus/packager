import Foundation

enum AppVersion {
    static let current: String = {
        guard let url = Bundle.module.url(forResource: "Version", withExtension: "txt"),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Packager version resource is missing")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }()
}
