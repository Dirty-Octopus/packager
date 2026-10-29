import Foundation
import AppKit

enum PackagerError: LocalizedError {
    case sourceMissing
    case expandFailed(String)
    case noComponents
    case buildFailed(String)
    case permissionDenied(String)
    case privilegeRequired(PrivilegeRequest)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            return T("The package no longer exists at that location.")
        case .expandFailed(let message):
            return message.isEmpty ? T("The package could not be expanded.") : message
        case .noComponents:
            return T("No installable components were found inside this package.")
        case .buildFailed(let message):
            return message
        case .permissionDenied(let message):
            return message
        case .privilegeRequired(let request):
            return request.message
        case .cancelled:
            return T("Operation canceled.")
        }
    }
}

// MARK: - Binary reading

struct BinaryInfo {
    var url: URL
    var relativePath: String
    var architectures: [String]
    var size: Int64
    var is32Bit: Bool
}

enum MachO {
    static func architectures(at url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 64), head.count >= 8 else { return nil }
        let bytes = [UInt8](head)
        let be = beUInt32(bytes, 0)

        switch be {
        case 0xCAFEBABE, 0xCAFEBABF:
            let is64 = be == 0xCAFEBABF
            let count = Int(beUInt32(bytes, 4))
            guard count > 0, count < 64 else { return nil }
            let entrySize = is64 ? 32 : 20
            let needed = 8 + count * entrySize
            var data = head
            if data.count < needed, let more = try? handle.read(upToCount: needed) {
                data.append(more)
            }
            guard data.count >= needed else { return nil }
            var archs: [String] = []
            for index in 0..<count {
                let offset = 8 + index * entrySize
                let cpu = beUInt32([UInt8](data), offset)
                if let name = cpuName(cpu), !archs.contains(name) {
                    archs.append(name)
                }
            }
            return archs.isEmpty ? nil : archs
        default:
            break
        }

        // Thin Mach-O. The magic tells us the header byte order.
        let le = leUInt32(bytes, 0)
        let thin32: UInt32 = 0xFEEDFACE
        let thin64: UInt32 = 0xFEEDFACF
        if be == thin32 || be == thin64 {
            return cpuName(beUInt32(bytes, 4)).map { [$0] }
        }
        if le == thin32 || le == thin64 {
            return cpuName(leUInt32(bytes, 4)).map { [$0] }
        }
        return nil
    }

    static func cpuName(_ cpu: UInt32) -> String? {
        switch cpu {
        case 7: return "i386"
        case 0x01000007: return "x86_64"
        case 12: return "arm"
        case 0x0100000C: return "arm64"
        case 0x0200000C: return "arm64_32"
        case 18: return "ppc"
        case 0x01000012: return "ppc64"
        default: return nil
        }
    }

    static func isLegacy(_ arch: String) -> Bool {
        ["i386", "arm", "ppc", "arm64_32"].contains(arch)
    }

    static func is32Bit(_ archs: [String]) -> Bool {
        archs.contains { isLegacy($0) }
    }

    private static func beUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    private static func leUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset + 3]) << 24
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset])
    }
}

// MARK: - File helpers

enum FileMagic {
    static func prefix(_ url: URL, length: Int) -> [UInt8] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        return [UInt8]((try? handle.read(upToCount: length)) ?? Data())
    }

    static func payloadKind(_ url: URL) -> String? {
        let bytes = prefix(url, length: 6)
        guard !bytes.isEmpty else { return nil }
        if bytes.count >= 2, bytes[0] == 0x1F, bytes[1] == 0x8B { return "gzip" }
        if bytes.count >= 3, bytes[0] == 0x42, bytes[1] == 0x5A, bytes[2] == 0x68 { return "bzip2" }
        if bytes.count >= 6, Array(bytes[0..<6]) == [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00] { return "xz" }
        if bytes.count >= 4, Array(bytes[0..<4]) == [0x28, 0xB5, 0x2F, 0xFD] { return "zstd" }
        if bytes.count >= 4, Array(bytes[0..<4]) == Array("xar!".utf8) { return "xar" }
        if bytes.count >= 6, Array(bytes[0..<6]) == Array("070707".utf8) { return "cpio" }
        return "raw"
    }

    static func isXAR(_ url: URL) -> Bool {
        Array(prefix(url, length: 4)) == Array("xar!".utf8)
    }
}

// MARK: - Inspector

enum PackageInspector {
    struct PayloadScan {
        var fileCount: Int = 0
        var bytes: Int64 = 0
        var binaries: [BinaryInfo] = []
        var scannedFiles: Int = 0
    }

    private static let fm = FileManager.default
    private static let maxScanFiles = 250_000
    private static let textExtensions: Set<String> = [
        "txt", "md", "html", "htm", "css", "js", "mjs", "json", "plist", "strings",
        "xml", "rtf", "png", "jpg", "jpeg", "gif", "pdf", "icns", "tiff", "heic",
        "webp", "svg", "mo", "nib", "car", "storyboard", "xib", "nib", "stringsdict",
        "lproj", "localizable", "map", "woff", "woff2", "ttf", "otf", "csv", "yaml",
        "yml", "conf", "ini", "log", "zip", "gz", "bz2", "xz", "dSYM"
    ]

    // MARK: Entry point

    static func inspect(source: URL, workRoot: URL, log: @escaping (String) -> Void) throws -> PackageInspection {
        let started = Date()
        try fm.createDirectory(at: workRoot, withIntermediateDirectories: true)

        let repack = workRoot.appendingPathComponent("repack", isDirectory: true)
        let full = workRoot.appendingPathComponent("full", isDirectory: true)
        try? fm.removeItem(at: repack)
        try? fm.removeItem(at: full)

        guard fm.fileExists(atPath: source.path) else { throw PackagerError.sourceMissing }

        var notes: [String] = []
        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let format: PackageFormat = isDirectory ? .bundle : .flatXAR
        log(isDirectory ? "Bundle package detected" : "Flat package detected")

        var fullExpanded = false
        if isDirectory {
            log(T("Copying bundle into the workspace"))
            do {
                try fm.copyItem(at: source, to: repack)
            } catch {
                throw PackagerError.expandFailed("Could not copy the bundle into the workspace: \(error.localizedDescription)")
            }
        } else {
            let magic = FileMagic.isXAR(source)
            if !magic {
                notes.append("This file does not have a XAR header; pkgutil will attempt a best-effort expansion.")
            }
            log(T("Expanding archive into the workspace"))
            let expand = Shell.run("/usr/sbin/pkgutil", ["--expand", source.path, repack.path])
            guard expand.succeeded else {
                if expand.indicatesPermissionFailure {
                    throw PackagerError.permissionDenied(expand.firstErrorLine ?? "Permission denied while expanding the package.")
                }
                throw PackagerError.expandFailed(expand.combined)
            }
        }

        log(T("Expanding payloads for binary inspection"))
        let directFull = Shell.run("/usr/sbin/pkgutil", ["--expand-full", source.path, full.path])
        fullExpanded = directFull.succeeded && fm.fileExists(atPath: full.path)
        if !fullExpanded {
            try? fm.removeItem(at: full)
            log(T("Trying component-wise payload expansion"))
            fullExpanded = expandComponentsIndividually(repack: repack, full: full, workRoot: workRoot, log: log)
        }
        if !fullExpanded {
            notes.append("Payload expansion was unavailable; binary checks are limited to declared metadata.")
            log(T("Payload expansion unavailable — structure only"))
        }

        let componentEntries = discoverComponents(in: repack)
        guard !componentEntries.isEmpty else { throw PackagerError.noComponents }

        let distributionURL = repack.appendingPathComponent("Distribution")
        let distribution = fm.fileExists(atPath: distributionURL.path) ? parseDistribution(distributionURL) : nil
        if let distribution, !distribution.constraints.isEmpty {
            log(T("Found %d system version constraint(s)", distribution.constraints.count))
        }

        var components: [PackageComponent] = []
        var componentNodes: [PackageNode] = []
        var scripts: [ScriptInfo] = []
        var allBinaries: [BinaryInfo] = []
        var totalFiles = 0
        var totalBytes: Int64 = 0
        var bit32 = 0

        for (relativePath, directory) in componentEntries {
            let info = PackageInfoFile.read(directory.appendingPathComponent("PackageInfo"))
            var component = buildComponent(
                relativePath: relativePath,
                directory: directory,
                info: info
            )

            let payloadArchive = directory.appendingPathComponent("Payload")
            var payloadNode: PackageNode?
            if fullExpanded {
                let payloadDir = full
                    .appendingPathComponent(relativePath)
                    .appendingPathComponent("Payload", isDirectory: true)
                if isDirectoryURL(payloadDir) {
                    let scan = scanPayload(at: payloadDir, baseRelativePath: relativePath)
                    component.payloadFileCount = scan.fileCount
                    component.payloadBytes = scan.bytes
                    component.binaryCount = scan.binaries.count
                    component.bit32Count = scan.binaries.filter(\.is32Bit).count
                    totalFiles += scan.fileCount
                    totalBytes += scan.bytes
                    allBinaries.append(contentsOf: scan.binaries)
                    bit32 += component.bit32Count

                    var budget = TreeBudget()
                    let tree = payloadTree(
                        dir: payloadDir,
                        name: "Payload",
                        depth: 0,
                        relative: relativePath,
                        budget: &budget
                    )
                    payloadNode = tree
                }
            }

            if payloadNode == nil, fm.fileExists(atPath: payloadArchive.path) {
                component.payloadArchiveKind = FileMagic.payloadKind(payloadArchive)
                let size = fileSize(payloadArchive)
                component.payloadBytes = size
                if let declared = info?.payloadFileCount { component.payloadFileCount = declared }
                payloadNode = PackageNode(
                    path: payloadArchive.path,
                    name: "Payload",
                    kind: .payloadArchive,
                    size: size,
                    note: component.payloadArchiveKind.map { "\($0) archive" },
                    isFileNode: true
                )
            }

            let componentScripts = loadScripts(directory: directory, relativePath: relativePath, info: info)
            component.scripts = componentScripts
            scripts.append(contentsOf: componentScripts)

            let scriptsNode: PackageNode? = componentScripts.isEmpty ? nil : {
                let children = componentScripts.map { script in
                    PackageNode(
                        path: script.url.path,
                        name: script.name,
                        kind: .script,
                        size: script.size,
                        risk: script.risk == .high ? .high : (script.risk == .caution ? .caution : .none),
                        note: script.findings.first,
                        isFileNode: true
                    )
                }
                return PackageNode(
                    path: directory.appendingPathComponent("Scripts").path,
                    name: "Scripts",
                    kind: .resources,
                    size: componentScripts.reduce(0) { $0 + $1.size },
                    note: "\(componentScripts.count) install script\(componentScripts.count == 1 ? "" : "s")",
                    children: children
                )
            }()

            let packageInfoNode = PackageNode(
                path: directory.appendingPathComponent("PackageInfo").path,
                name: "PackageInfo",
                kind: .packageInfo,
                size: fileSize(directory.appendingPathComponent("PackageInfo")),
                note: "identifier · \(component.identifier)",
                isFileNode: true
            )

            let bomNode: PackageNode? = component.hasBom ? PackageNode(
                path: directory.appendingPathComponent("Bom").path,
                name: "Bom",
                kind: .bom,
                size: fileSize(directory.appendingPathComponent("Bom")),
                note: "Bill of materials",
                isFileNode: true
            ) : nil

            var children: [PackageNode] = []
            if let payloadNode { children.append(payloadNode) }
            if let scriptsNode { children.append(scriptsNode) }
            if let bomNode { children.append(bomNode) }
            children.append(packageInfoNode)
            if let resources = resourcesNode(directory: directory) { children.append(resources) }

            var archNote = component.installLocation
            if let arch = component.declaredArch { archNote += " · declares \(arch)" }

            let node = PackageNode(
                path: directory.path,
                name: component.displayName,
                kind: .component,
                size: (component.payloadBytes > 0 ? component.payloadBytes : nil),
                is32Bit: component.bit32Count > 0,
                note: archNote,
                children: children
            )
            componentNodes.append(node)
            components.append(component)
            log(T("Parsed %@", component.displayName))
        }

        // Product-level distribution node
        var rootChildren: [PackageNode] = []
        if fm.fileExists(atPath: distributionURL.path) {
            var noteParts: [String] = []
            if let title = distribution?.title { noteParts.append(title) }
            if let constraints = distribution?.constraints, !constraints.isEmpty {
                noteParts.append("\(constraints.count) OS constraint\(constraints.count == 1 ? "" : "s")")
            }
            rootChildren.append(PackageNode(
                path: distributionURL.path,
                name: "Distribution",
                kind: .distribution,
                size: fileSize(distributionURL),
                note: noteParts.isEmpty ? "Installer distribution script" : noteParts.joined(separator: " · "),
                isFileNode: true
            ))
        }
        rootChildren.append(contentsOf: componentNodes)

        let title = distribution?.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? source.deletingPathExtension().lastPathComponent

        let stats = InspectionStats(
            components: components.count,
            payloadFiles: totalFiles,
            payloadBytes: totalBytes,
            binaries: allBinaries.count,
            bit32Binaries: bit32,
            scripts: scripts.count,
            highRiskScripts: scripts.filter { $0.risk == .high }.count,
            relocatableComponents: components.filter(\.relocatable).count,
            osConstraints: distribution?.constraints.count ?? 0
        )

        let root = PackageNode(
            path: source.path,
            name: title,
            kind: .product,
            size: totalBytes > 0 ? totalBytes : fileSize(source),
            is32Bit: bit32 > 0,
            note: "\(components.count) component\(components.count == 1 ? "" : "s")",
            children: rootChildren
        )

        let signature = signatureDescription(for: source)
        let issues = buildIssues(
            format: format,
            distribution: distribution,
            components: components,
            scripts: scripts,
            binaries: allBinaries,
            stats: stats,
            signature: signature,
            payloadExpanded: fullExpanded,
            language: .en
        )
        let issuesZH = buildIssues(
            format: format,
            distribution: distribution,
            components: components,
            scripts: scripts,
            binaries: allBinaries,
            stats: stats,
            signature: signature,
            payloadExpanded: fullExpanded,
            language: .zhHans
        )

        log(T("Inspection complete · %d components · %d payload files · %d legacy binaries", stats.components, stats.payloadFiles, stats.bit32Binaries))

        return PackageInspection(
            sourceURL: source,
            title: title,
            format: format,
            signature: signature,
            root: root,
            components: components,
            scripts: scripts,
            issues: issues,
            issuesZH: issuesZH,
            distribution: distribution,
            stats: stats,
            workRoot: workRoot,
            repackDir: repack,
            fullDir: fullExpanded ? full : nil,
            payloadExpanded: fullExpanded,
            duration: Date().timeIntervalSince(started),
            notes: Array(notes.prefix(40))
        )
    }

    // MARK: Component discovery

    /// Bundle-style products (and some unusual flat products) cannot be expanded
    /// with a single `--expand-full`. Flatten each component, then expand its payload.
    private static func expandComponentsIndividually(
        repack: URL,
        full: URL,
        workRoot: URL,
        log: @escaping (String) -> Void
    ) -> Bool {
        let components = discoverComponents(in: repack)
        guard !components.isEmpty else { return false }
        let staging = workRoot.appendingPathComponent("component-expansion", isDirectory: true)
        try? fm.removeItem(at: staging)
        try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try? fm.createDirectory(at: full, withIntermediateDirectories: true)

        var expandedAny = false
        for (relativePath, directory) in components {
            let payload = directory.appendingPathComponent("Payload")
            guard fm.fileExists(atPath: payload.path) else { continue }
            let slug = relativePath.isEmpty ? "root" : relativePath.replacingOccurrences(of: "/", with: "-")
            let flatURL = staging.appendingPathComponent("\(slug).pkg")
            let flatten = Shell.run("/usr/sbin/pkgutil", ["--flatten", directory.path, flatURL.path])
            guard flatten.succeeded else { continue }
            let destination = full.appendingPathComponent(relativePath)
            try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let expand = Shell.run("/usr/sbin/pkgutil", ["--expand-full", flatURL.path, destination.path])
            try? fm.removeItem(at: flatURL)
            if expand.succeeded {
                expandedAny = true
            } else {
                log(T("Could not expand payload for %@", directory.lastPathComponent))
            }
        }
        try? fm.removeItem(at: staging)
        return expandedAny
    }


    private static func discoverComponents(in root: URL) -> [(String, URL)] {
        var results: [(String, URL)] = []
        if fm.fileExists(atPath: root.appendingPathComponent("PackageInfo").path) {
            results.append(("", root))
        }

        func walk(_ directory: URL, relative: String, depth: Int) {
            guard depth <= 4 else { return }
            let entries = (try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries {
                guard isDirectoryURL(entry) else { continue }
                let name = entry.lastPathComponent
                if ["Scripts", "Payload", "Resources", "Contents"].contains(name) { continue }
                let childRelative = relative.isEmpty ? name : relative + "/" + name
                if fm.fileExists(atPath: entry.appendingPathComponent("PackageInfo").path) {
                    results.append((childRelative, entry))
                } else {
                    walk(entry, relative: childRelative, depth: depth + 1)
                }
            }
        }
        walk(root, relative: "", depth: 0)
        return results
    }

    private static func buildComponent(relativePath: String, directory: URL, info: PackageInfoFile?) -> PackageComponent {
        let identifier = (info?.identifier).flatMap { $0.isEmpty ? nil : $0 } ?? relativePath
        let version = info?.version ?? "—"
        let installLocation = info?.installLocation ?? "/"
        let relocatable = info?.relocatable ?? false
        let declaredArch = info?.declaredArch
        let payloadURL = directory.appendingPathComponent("Payload")
        let hasPayload = fm.fileExists(atPath: payloadURL.path)
        let hasBom = fm.fileExists(atPath: directory.appendingPathComponent("Bom").path)
        return PackageComponent(
            relativePath: relativePath,
            directory: directory,
            identifier: identifier,
            version: version,
            installLocation: installLocation,
            relocatable: relocatable,
            declaredArch: declaredArch,
            payloadArchiveKind: hasPayload && !isDirectoryURL(payloadURL) ? FileMagic.payloadKind(payloadURL) : nil,
            hasBom: hasBom,
            hasPayload: hasPayload
        )
    }

    private static func loadScripts(directory: URL, relativePath: String, info: PackageInfoFile?) -> [ScriptInfo] {
        let scriptsDirectory = directory.appendingPathComponent("Scripts", isDirectory: true)
        guard isDirectoryURL(scriptsDirectory) else { return [] }
        let declaredNames: Set<String> = Set(info?.scriptEntries.map(\.file) ?? [])

        let entries = (try? fm.contentsOfDirectory(
            at: scriptsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var scripts: [ScriptInfo] = []
        for entry in entries {
            let name = entry.lastPathComponent
            if name == ".DS_Store" || name.hasPrefix("._") { continue }
            let isRegular = (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if !isRegular { continue }
            let risk = analyzeScript(at: entry)
            scripts.append(ScriptInfo(
                componentRelativePath: relativePath,
                name: name,
                url: entry,
                size: fileSize(entry),
                risk: risk.risk,
                findings: risk.findings
            ))
        }

        for name in declaredNames where !scripts.contains(where: { $0.name == name }) {
            let url = scriptsDirectory.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                let risk = analyzeScript(at: url)
                scripts.append(ScriptInfo(
                    componentRelativePath: relativePath,
                    name: name,
                    url: url,
                    size: fileSize(url),
                    risk: risk.risk,
                    findings: risk.findings
                ))
            }
        }

        return scripts.sorted { $0.name < $1.name }
    }

    private static func analyzeScript(at url: URL) -> (risk: ScriptRisk, findings: [String]) {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count < 1_500_000,
              let text = String(data: data, encoding: .utf8)
        else {
            return (.caution, ["Binary or encoded script"])
        }

        let patterns: [(String, String, ScriptRisk)] = [
            ("rm -rf /", "Deletes absolute system paths", .high),
            ("rm -rf", "Recursive deletion", .caution),
            ("spctl --master-disable", "Disables Gatekeeper", .high),
            ("csrutil", "Touches System Integrity Protection", .high),
            ("kextload", "Loads kernel extensions", .high),
            ("/System/", "Writes inside /System", .high),
            ("| sh", "Pipes remote content into a shell", .high),
            ("| bash", "Pipes remote content into a shell", .high),
            ("curl ", "Downloads from the network", .caution),
            ("wget ", "Downloads from the network", .caution),
            ("sudo ", "Escalates privileges", .caution),
            ("launchctl", "Manages launchd services", .caution),
            ("/Library/LaunchDaemons", "Installs a persistent daemon", .high),
            ("defaults write", "Modifies preferences", .caution),
            ("chmod 777", "Makes files world-writable", .caution),
            ("nvram", "Writes firmware variables", .high),
            ("pkgutil --forget", "Forgets receipt data", .caution)
        ]

        var findings: [String] = []
        var risk: ScriptRisk = .none
        for (needle, description, level) in patterns where text.lowercased().contains(needle.lowercased()) {
            if !findings.contains(description) {
                findings.append(description)
            }
            if level > risk { risk = level }
        }
        if text.contains("system.version") || text.contains("os.version") {
            findings.append("Checks the host OS version")
            if risk < .caution { risk = .caution }
        }
        return (risk, findings)
    }

    // MARK: Payload scanning and tree

    private static func scanPayload(at root: URL, baseRelativePath: String) -> PayloadScan {
        var scan = PayloadScan()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return scan }

        for case let url as URL in enumerator {
            scan.scannedFiles += 1
            if scan.scannedFiles > maxScanFiles { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
            if values?.isRegularFile != true { continue }
            scan.fileCount += 1
            let size = Int64(values?.fileSize ?? 0)
            scan.bytes += size
            guard size >= 512 else { continue }
            let ext = url.pathExtension.lowercased()
            if textExtensions.contains(ext) { continue }
            guard let archs = MachO.architectures(at: url) else { continue }
            let relative = url.path.replacingOccurrences(of: root.path, with: baseRelativePath)
            scan.binaries.append(BinaryInfo(
                url: url,
                relativePath: relative,
                architectures: archs,
                size: size,
                is32Bit: MachO.is32Bit(archs)
            ))
        }
        return scan
    }

    private struct TreeBudget {
        var nodes = 0
        let maxNodes = 1600
        let maxChildren = 60
        let maxDepth = 8
    }

    private static func payloadTree(
        dir: URL,
        name: String,
        depth: Int,
        relative: String,
        budget: inout TreeBudget
    ) -> PackageNode {
        budget.nodes += 1
        let path = dir.path
        var node = PackageNode(
            path: path,
            name: name,
            kind: depth == 0 ? .payload : .folder,
            size: nil,
            note: nil
        )

        guard depth < budget.maxDepth, budget.nodes < budget.maxNodes else {
            let count = childCount(of: dir)
            node.hiddenCount = count
            node.note = count > 0 ? "\(Fmt.count(count)) items" : nil
            return node
        }

        let entries = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let sorted = entries
            .filter { $0.lastPathComponent != ".DS_Store" && !$0.lastPathComponent.hasPrefix("._") }
            .sorted { lhs, rhs in
                let ldir = isDirectoryURL(lhs)
                let rdir = isDirectoryURL(rhs)
                if ldir != rdir { return ldir }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }

        var children: [PackageNode] = []
        var totalSize: Int64 = 0

        for entry in sorted {
            if budget.nodes >= budget.maxNodes {
                node.hiddenCount = sorted.count - children.count
                break
            }
            if children.count >= budget.maxChildren {
                node.hiddenCount = sorted.count - children.count
                break
            }

            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey])
            let isDir = values?.isDirectory ?? false
            let isSymlink = values?.isSymbolicLink ?? false

            if isDir && !isSymlink {
                let child = payloadTree(
                    dir: entry,
                    name: entry.lastPathComponent,
                    depth: depth + 1,
                    relative: relative,
                    budget: &budget
                )
                if let size = directorySizeShallow(entry) { totalSize += size }
                children.append(child)
            } else {
                let size = Int64(values?.fileSize ?? 0)
                totalSize += size
                let kind: NodeKind
                var archs: [String] = []
                var is32 = false
                if !isSymlink, let detected = MachO.architectures(at: entry) {
                    kind = .binary
                    archs = detected
                    is32 = MachO.is32Bit(detected)
                } else {
                    kind = .file
                }
                var child = PackageNode(
                    path: entry.path,
                    name: entry.lastPathComponent,
                    kind: kind,
                    size: size,
                    architectures: archs,
                    is32Bit: is32,
                    isFileNode: true
                )
                if isSymlink { child.note = "Symbolic link" }
                children.append(child)
            }
        }

        node.children = children
        node.size = totalSize > 0 ? totalSize : nil
        if node.hiddenCount > 0 {
            node.note = "\(Fmt.count(node.hiddenCount)) more items"
        }
        return node
    }

    private static func resourcesNode(directory: URL) -> PackageNode? {
        let resources = directory.appendingPathComponent("Resources", isDirectory: true)
        guard isDirectoryURL(resources) else { return nil }
        let entries = ((try? fm.contentsOfDirectory(at: resources, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix("._") && $0.lastPathComponent != ".DS_Store" }
        let children = entries.prefix(40).map { entry -> PackageNode in
            let size = fileSize(entry)
            return PackageNode(
                path: entry.path,
                name: entry.lastPathComponent,
                kind: isDirectoryURL(entry) ? .folder : .file,
                size: size,
                isFileNode: !isDirectoryURL(entry)
            )
        }
        return PackageNode(
            path: resources.path,
            name: "Resources",
            kind: .resources,
            children: children,
            hiddenCount: max(0, entries.count - children.count)
        )
    }

    // MARK: Distribution

    private static func parseDistribution(_ url: URL) -> DistributionInfo? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        var info = DistributionInfo()
        info.hasAllowedOSVersions = text.contains("allowed-os-versions")
        info.hasVersionScript = text.contains("system.version") || text.contains("os.version")

        if let doc = try? XMLDocument(contentsOf: url, options: []) {
            info.title = firstAttribute(in: doc.rootElement(), named: "title")
            info.productVersion = firstAttribute(in: doc.rootElement(), named: "product-version")

            var constraints: [OSConstraint] = []
            func walk(_ node: XMLNode, ancestors: [String]) {
                if let element = node as? XMLElement {
                    let name = element.name ?? ""
                    if name == "product" {
                        if info.title == nil { info.title = element.attribute(forName: "title")?.stringValue }
                        if info.productVersion == nil { info.productVersion = element.attribute(forName: "product-version")?.stringValue }
                    }
                    if name == "title", let value = element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                        info.title = value
                    }
                    if name == "os-version" {
                        let minValue = element.attribute(forName: "min")?.stringValue
                        let maxValue = element.attribute(forName: "max")?.stringValue
                        if minValue != nil || maxValue != nil {
                            let source: String
                            if ancestors.contains("allowed-os-versions") {
                                source = "allowed-os-versions"
                            } else if ancestors.contains("volume-check") {
                                source = "volume-check"
                            } else if ancestors.contains("installation-check") {
                                source = "installation-check"
                            } else {
                                source = "distribution"
                            }
                            constraints.append(OSConstraint(
                                id: "\(source)-\(minValue ?? "")-\(maxValue ?? "")",
                                minVersion: minValue,
                                maxVersion: maxValue,
                                source: source,
                                isBlocking: maxValue != nil || ancestors.contains("allowed-os-versions")
                            ))
                        }
                    }
                    for child in element.children ?? [] {
                        walk(child, ancestors: ancestors + [name])
                    }
                } else {
                    for child in node.children ?? [] {
                        walk(child, ancestors: ancestors)
                    }
                }
            }
            if let root = doc.rootElement() {
                walk(root, ancestors: [])
            }
            var seen = Set<String>()
            info.constraints = constraints.filter { seen.insert($0.id).inserted }
        } else {
            info.title = firstMatch(in: text, pattern: "product[^>]*title=\"([^\"]+)\"")
            let regex = try? NSRegularExpression(pattern: "<os-version([^>]*)>", options: [])
            let nsText = text as NSString
            regex?.enumerateMatches(in: text, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
                guard let match, match.numberOfRanges > 1 else { return }
                let attributes = nsText.substring(with: match.range(at: 1))
                let minValue = firstMatch(in: attributes, pattern: "min=\"([^\"]+)\"")
                let maxValue = firstMatch(in: attributes, pattern: "max=\"([^\"]+)\"")
                if minValue != nil || maxValue != nil {
                    info.constraints.append(OSConstraint(
                        id: "regex-\(minValue ?? "")-\(maxValue ?? "")",
                        minVersion: minValue,
                        maxVersion: maxValue,
                        source: "distribution",
                        isBlocking: maxValue != nil
                    ))
                }
            }
        }
        return info
    }

    private static func firstAttribute(in element: XMLElement?, named name: String) -> String? {
        element?.attribute(forName: name)?.stringValue
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    // MARK: Issues

    private static func buildIssues(
        format: PackageFormat,
        distribution: DistributionInfo?,
        components: [PackageComponent],
        scripts: [ScriptInfo],
        binaries: [BinaryInfo],
        stats: InspectionStats,
        signature: String,
        payloadExpanded: Bool,
        language: AppLanguage
    ) -> [PackageIssue] {
        var issues: [PackageIssue] = []

        if let distribution, !distribution.constraints.isEmpty {
            let hasMax = distribution.constraints.contains { $0.isBlocking }
            let values = distribution.constraints.map(\.display).joined(separator: ", ")
            var message = L10n.s(
                "The Distribution script gates installation on system version (%@).",
                language,
                values
            )
            if hasMax {
                message += L10n.s(" A maximum bound will block installation on every newer macOS release.", language)
            }
            if distribution.hasVersionScript {
                message += L10n.s(" Installer JavaScript also inspects the host OS version.", language)
            }
            issues.append(PackageIssue(
                id: "os-version",
                severity: hasMax ? .critical : .warning,
                category: .osVersion,
                title: L10n.s("System version gate", language),
                message: message,
                paths: ["Distribution"],
                fix: .versionLimits
            ))
        }

        let declared32 = components.filter { component in
            let arch = component.declaredArch?.lowercased() ?? ""
            return arch.contains("i386") || arch.contains("ppc") || arch == "arm"
        }
        if !declared32.isEmpty {
            issues.append(PackageIssue(
                id: "declared-32",
                severity: .warning,
                category: .architecture,
                title: L10n.s("32-bit architecture declared", language),
                message: declared32.map {
                    L10n.s("%@ declares %@", language, $0.displayName, $0.declaredArch ?? L10n.s("legacy arch", language))
                }.joined(separator: " · "),
                paths: declared32.map(\.relativePath).filter { !$0.isEmpty }
            ))
        }

        if stats.bit32Binaries > 0 {
            let only32 = stats.binaries > 0 && stats.bit32Binaries == stats.binaries
            let examples = binaries.filter(\.is32Bit).prefix(6).map(\.relativePath)
            issues.append(PackageIssue(
                id: "binaries-32",
                severity: only32 ? .critical : .warning,
                category: .architecture,
                title: L10n.s("%d 32-bit binaries found", language, stats.bit32Binaries),
                message: L10n.s(
                    only32
                        ? "Every detected executable is 32-bit only. macOS 10.15 and later cannot run these slices at all."
                        : "Some executable slices target i386, PowerPC, or 32-bit ARM. They cannot load on current macOS releases.",
                    language
                ),
                paths: Array(examples)
            ))
        }

        func scriptLabel(_ script: ScriptInfo) -> String {
            let component = components.first { $0.relativePath == script.componentRelativePath }
            let prefix = component?.identifier.nilIfEmpty ?? script.componentRelativePath
            return prefix.isEmpty ? script.name : "\(prefix)/\(script.name)"
        }

        if stats.relocatableComponents > 0 {
            let names = components.filter(\.relocatable).map(\.displayName)
            issues.append(PackageIssue(
                id: "relocatable",
                severity: .info,
                category: .relocatable,
                title: L10n.s("Relocatable components", language),
                message: L10n.s(
                    "%d component(s) allow Installer to relocate the payload to another volume: %@.",
                    language,
                    stats.relocatableComponents,
                    names.joined(separator: ", ")
                ),
                paths: ["PackageInfo"],
                fix: .relocatable
            ))
        }

        let highRisk = scripts.filter { $0.risk == .high }
        if !highRisk.isEmpty {
            let findings = Set(highRisk.flatMap(\.findings)).sorted().map {
                L10n.s($0, language)
            }
            issues.append(PackageIssue(
                id: "scripts-high",
                severity: .warning,
                category: .scripts,
                title: L10n.s("%d high-risk install script(s)", language, highRisk.count),
                message: L10n.s(
                    "%@ — %@. Stripping scripts changes install behavior; keep them if the package needs them.",
                    language,
                    highRisk.map(scriptLabel).joined(separator: ", "),
                    findings.joined(separator: "; ")
                ),
                paths: highRisk.map(scriptLabel),
                fix: .scripts
            ))
        } else if !scripts.isEmpty {
            issues.append(PackageIssue(
                id: "scripts-info",
                severity: .info,
                category: .scripts,
                title: L10n.s("%d install script(s) present", language, scripts.count),
                message: L10n.s(
                    "No dangerous commands were detected, but install scripts still run as root at install time.",
                    language
                ),
                paths: scripts.prefix(8).map(scriptLabel)
            ))
        }

        if signature.lowercased().contains("signed") {
            issues.append(PackageIssue(
                id: "signature",
                severity: .info,
                category: .signature,
                title: L10n.s("Signed package", language),
                message: L10n.s(
                    "Status: %@. Repackaging rewrites the archive, so the existing signature will not carry over to the new product.",
                    language,
                    signature
                ),
                paths: []
            ))
        }

        if !payloadExpanded {
            issues.append(PackageIssue(
                id: "payload-skipped",
                severity: .warning,
                category: .integrity,
                title: L10n.s("Payload not expanded", language),
                message: L10n.s(
                    "The payload could not be expanded in the workspace, so binary architecture checks are limited to declared metadata.",
                    language
                ),
                paths: []
            ))
        }

        if format == .bundle {
            issues.append(PackageIssue(
                id: "bundle",
                severity: .info,
                category: .integrity,
                title: L10n.s("Legacy bundle package", language),
                message: L10n.s(
                    "Bundle-style packages are rebuilt into a flat XAR archive for modern macOS.",
                    language
                ),
                paths: []
            ))
        }

        return issues.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            return lhs.title < rhs.title
        }
    }

    // MARK: Misc

    static func signatureDescription(for url: URL) -> String {
        let result = Shell.run("/usr/sbin/pkgutil", ["--check-signature", url.path])
        let text = result.combined
        if text.isEmpty { return "Unknown" }
        if text.localizedCaseInsensitiveContains("not signed") { return "Unsigned" }
        if text.localizedCaseInsensitiveContains("Status: signed") || text.localizedCaseInsensitiveContains("signed by") {
            if let line = text.components(separatedBy: .newlines).first(where: { $0.localizedCaseInsensitiveContains("signed") }) {
                return line.trimmingCharacters(in: .whitespaces)
            }
            return "Signed"
        }
        if text.localizedCaseInsensitiveContains("unsigned") { return "Unsigned" }
        return "Unknown"
    }

    static func loadPlist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )) as? [String: Any]
    }

    private static func isDirectoryURL(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]),
              let size = values.fileSize
        else { return 0 }
        return Int64(size)
    }

    private static func directorySizeShallow(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.totalFileSizeKey]) else { return nil }
        return values.totalFileSize.map(Int64.init)
    }

    private static func childCount(of dir: URL) -> Int {
        ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0 != ".DS_Store" }
            .count
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
