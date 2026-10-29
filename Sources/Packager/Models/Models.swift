import Foundation

// MARK: - Tree

enum NodeKind: String, Hashable {
    case product
    case component
    case payload
    case payloadArchive
    case folder
    case binary
    case script
    case packageInfo
    case distribution
    case bom
    case resources
    case file
    case truncated
    case check

    var symbol: String {
        switch self {
        case .product: return "shippingbox.fill"
        case .component: return "puzzlepiece.extension.fill"
        case .payload: return "archivebox.fill"
        case .payloadArchive: return "doc.zipper"
        case .folder: return "folder.fill"
        case .binary: return "gearshape.2.fill"
        case .script: return "curlybraces"
        case .packageInfo: return "list.bullet.rectangle.portrait"
        case .distribution: return "doc.text"
        case .bom: return "tablecells"
        case .resources: return "photo.on.rectangle.angled"
        case .file: return "doc.fill"
        case .truncated: return "ellipsis"
        case .check: return "checkmark.seal.fill"
        }
    }
}

enum NodeRisk: String, Hashable {
    case none
    case caution
    case high
}

struct PackageNode: Identifiable, Hashable {
    var path: String
    var name: String
    var kind: NodeKind
    var size: Int64? = nil
    var architectures: [String] = []
    var is32Bit: Bool = false
    var risk: NodeRisk = .none
    var note: String? = nil
    var children: [PackageNode] = []
    var hiddenCount: Int = 0
    var isFileNode: Bool = false

    var id: String { "\(kind.rawValue)|\(path)|\(name)" }
    var hasChildren: Bool { !children.isEmpty }

    var iconTint: String {
        switch kind {
        case .product: return "accent"
        case .component: return "component"
        case .payload, .payloadArchive: return "payload"
        case .folder: return "folder"
        case .binary: return is32Bit ? "critical" : "binary"
        case .script: return risk == .high ? "critical" : "script"
        case .distribution, .packageInfo: return "config"
        case .bom: return "bom"
        case .resources: return "resources"
        case .file, .truncated, .check: return "muted"
        }
    }

    var archSummary: String? {
        guard !architectures.isEmpty else { return nil }
        if is32Bit {
            return architectures.joined(separator: " · ")
        }
        return architectures.count > 1 ? architectures.joined(separator: " · ") : nil
    }

    func flattened(expanded: Set<String>, depth: Int = 0) -> [(node: PackageNode, depth: Int)] {
        var rows: [(PackageNode, Int)] = [(self, depth)]
        if expanded.contains(id) {
            for child in children {
                rows.append(contentsOf: child.flattened(expanded: expanded, depth: depth + 1))
            }
        }
        return rows
    }

    func filtered(matching predicate: (PackageNode) -> Bool) -> PackageNode? {
        let kids = children.compactMap { $0.filtered(matching: predicate) }
        if predicate(self) || !kids.isEmpty {
            var copy = self
            copy.children = kids
            return copy
        }
        return nil
    }

    func allNodes() -> [PackageNode] {
        [self] + children.flatMap { $0.allNodes() }
    }

    var allExpandableIDs: Set<String> {
        var set = Set<String>()
        if hasChildren { set.insert(id) }
        for child in children { set.formUnion(child.allExpandableIDs) }
        return set
    }
}

// MARK: - Issues

enum Severity: Int, Comparable {
    case critical = 0
    case warning = 1
    case info = 2

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .critical: return "Critical"
        case .warning: return "Warning"
        case .info: return "Note"
        }
    }

    var symbol: String {
        switch self {
        case .critical: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

enum IssueCategory: String, Hashable {
    case architecture
    case osVersion
    case relocatable
    case scripts
    case signature
    case integrity

    var title: String {
        switch self {
        case .architecture: return "Architecture"
        case .osVersion: return "OS compatibility"
        case .relocatable: return "Relocation"
        case .scripts: return "Scripts"
        case .signature: return "Signature"
        case .integrity: return "Integrity"
        }
    }
}

enum FixKind: String, Hashable {
    case versionLimits
    case relocatable
    case scripts
}

struct PackageIssue: Identifiable, Hashable {
    var id: String
    var severity: Severity
    var category: IssueCategory
    var title: String
    var message: String
    var paths: [String] = []
    var fix: FixKind? = nil
}

// MARK: - Scripts

enum ScriptRisk: Int, Comparable {
    case none = 0
    case caution = 1
    case high = 2

    static func < (lhs: ScriptRisk, rhs: ScriptRisk) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .none: return "Standard"
        case .caution: return "Review"
        case .high: return "High risk"
        }
    }
}

struct ScriptInfo: Identifiable, Hashable {
    var id: String { "\(componentRelativePath)/\(name)" }
    var componentRelativePath: String
    var name: String
    var url: URL
    var size: Int64
    var risk: ScriptRisk
    var findings: [String]

    var kindLabel: String { name }
}

// MARK: - Components

struct OSConstraint: Identifiable, Hashable {
    var id: String
    var minVersion: String?
    var maxVersion: String?
    var source: String
    var isBlocking: Bool

    var display: String {
        switch (minVersion, maxVersion) {
        case let (min?, max?): return "min \(min) · max \(max)"
        case let (min?, nil): return "min \(min)"
        case let (nil, max?): return "max \(max)"
        default: return "version bound"
        }
    }
}

struct DistributionInfo: Hashable {
    var title: String?
    var productVersion: String?
    var constraints: [OSConstraint] = []
    var hasAllowedOSVersions: Bool = false
    var hasVersionScript: Bool = false
}

struct PackageComponent: Identifiable, Hashable {
    var id: String { relativePath.isEmpty ? "root" : relativePath }
    var relativePath: String
    var directory: URL
    var identifier: String
    var version: String
    var installLocation: String
    var relocatable: Bool
    var declaredArch: String?
    var payloadArchiveKind: String?
    var payloadFileCount: Int = 0
    var payloadBytes: Int64 = 0
    var binaryCount: Int = 0
    var bit32Count: Int = 0
    var scripts: [ScriptInfo] = []
    var hasBom: Bool = false
    var hasPayload: Bool = false

    var displayName: String { identifier.isEmpty ? relativePath : identifier }
}

// MARK: - Inspection

enum PackageFormat: String {
    case flatXAR = "Flat XAR"
    case bundle = "Bundle"
    case unknown = "Unknown"

    var symbol: String {
        switch self {
        case .flatXAR: return "shippingbox.fill"
        case .bundle: return "folder.fill"
        case .unknown: return "questionmark.folder.fill"
        }
    }

    var description: String {
        switch self {
        case .flatXAR: return "Flat package · XAR archive"
        case .bundle: return "Bundle package · MPKG directory"
        case .unknown: return "Unrecognized container"
        }
    }
}

struct InspectionStats: Hashable {
    var components: Int = 0
    var payloadFiles: Int = 0
    var payloadBytes: Int64 = 0
    var binaries: Int = 0
    var bit32Binaries: Int = 0
    var scripts: Int = 0
    var highRiskScripts: Int = 0
    var relocatableComponents: Int = 0
    var osConstraints: Int = 0
}

struct PackageInspection {
    var sourceURL: URL
    var title: String
    var format: PackageFormat
    var signature: String
    var root: PackageNode
    var components: [PackageComponent]
    var scripts: [ScriptInfo]
    var issues: [PackageIssue]
    var issuesZH: [PackageIssue] = []
    var distribution: DistributionInfo?
    var stats: InspectionStats
    var workRoot: URL
    var repackDir: URL
    var fullDir: URL?
    var payloadExpanded: Bool
    var duration: TimeInterval
    var notes: [String]

    func issues(for language: AppLanguage) -> [PackageIssue] {
        language == .zhHans && !issuesZH.isEmpty ? issuesZH : issues
    }
}

// MARK: - Rebuild

struct RebuildOptions: Equatable {
    var removeVersionLimits: Bool = true
    var removeRelocatable: Bool = true
    var stripHighRiskScripts: Bool = false
    var outputDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    var outputName: String = ""

    var hasAnyChange: Bool {
        removeVersionLimits || removeRelocatable || stripHighRiskScripts
    }

    static func defaults(for inspection: PackageInspection) -> RebuildOptions {
        var options = RebuildOptions()
        options.removeVersionLimits = inspection.stats.osConstraints > 0
        options.removeRelocatable = inspection.stats.relocatableComponents > 0
        options.stripHighRiskScripts = false
        options.outputName = Self.defaultName(for: inspection.sourceURL)
        return options
    }

    static func defaultName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        return "\(base)-modernized.pkg"
    }
}

struct PrivilegeRequest {
    var message: String
    var command: String
    var sourceURL: URL
    var destinationURL: URL
    var size: Int64
    var duration: TimeInterval
    var appliedFixCount: Int
    var removedScriptNames: [String]
}

struct BuildResult {
    var outputURL: URL
    var size: Int64
    var duration: TimeInterval
    var appliedFixCount: Int
    var removedScriptNames: [String]
    var verified: Bool
}

enum BuildStage {
    case preparing
    case sanitizing
    case repackaging
    case verifying
    case finished
}

// MARK: - Run state

enum LogLevel: String {
    case info
    case success
    case warning
    case error
    case command
}

struct LogEntry: Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var level: LogLevel
    var text: String
    var detail: String? = nil
}
