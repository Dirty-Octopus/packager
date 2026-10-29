import Foundation

enum Fmt {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter
    }()

    static func size(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        if value < 1024 { return "\(value) B" }
        return bytes.string(fromByteCount: value)
    }

    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func duration(_ value: TimeInterval) -> String {
        value < 1 ? String(format: "%.0f ms", value * 1000) : String(format: "%.1f s", value)
    }
}
