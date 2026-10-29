import Foundation
import Darwin

enum CLIRunner {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        if arguments.contains("--version") {
            print("Packager 1.0")
            exit(0)
        }
        guard let inspectIndex = arguments.firstIndex(of: "--inspect") else { return false }
        guard inspectIndex + 1 < arguments.count else {
            FileHandle.standardError.write(Data("usage: Packager --inspect <path> [--rebuild <dir>] [--all] [--name <file>]\n".utf8))
            exit(2)
        }

        let source = URL(fileURLWithPath: arguments[inspectIndex + 1])
        let workRoot = Workspace.root.appendingPathComponent("cli-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do {
            let inspection = try PackageInspector.inspect(source: source, workRoot: workRoot) { line in
                print("  · \(line)")
            }
            printReport(inspection)

            if let rebuildIndex = arguments.firstIndex(of: "--rebuild"), rebuildIndex + 1 < arguments.count {
                var options = RebuildOptions.defaults(for: inspection)
                options.outputDirectory = URL(fileURLWithPath: arguments[rebuildIndex + 1], isDirectory: true)
                if arguments.contains("--all") {
                    options.removeVersionLimits = true
                    options.removeRelocatable = true
                    options.stripHighRiskScripts = true
                }
                if let nameIndex = arguments.firstIndex(of: "--name"), nameIndex + 1 < arguments.count {
                    options.outputName = arguments[nameIndex + 1]
                }
                print("\nRebuilding with options: versionLimits=\(options.removeVersionLimits) relocatable=\(options.removeRelocatable) scripts=\(options.stripHighRiskScripts)")
                do {
                    let result = try PackageRebuilder.rebuild(
                        source: source,
                        inspection: inspection,
                        options: options
                    ) { line in
                        print("  · \(line)")
                    }
                    print("\nBUILD OK")
                    print("  output: \(result.outputURL.path)")
                    print("  size: \(Fmt.size(result.size))")
                    print("  duration: \(Fmt.duration(result.duration))")
                    print("  fixes: \(result.appliedFixCount)")
                } catch let error as PackagerError {
                    print("\nBUILD FAILED: \(error.localizedDescription)")
                    if case .privilegeRequired(let request) = error {
                        print("  privilege command: \(request.command)")
                    }
                    try? FileManager.default.removeItem(at: workRoot)
                    exit(1)
                }
            }

            try? FileManager.default.removeItem(at: workRoot)
            exit(0)
        } catch {
            print("INSPECT FAILED: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: workRoot)
            exit(1)
        }
    }

    private static func printReport(_ inspection: PackageInspection) {
        print("\n════ PACKAGER REPORT ════")
        print("title:       \(inspection.title)")
        print("format:      \(inspection.format.rawValue)")
        print("signature:   \(inspection.signature)")
        print("source:      \(inspection.sourceURL.path)")
        print("workspace:   \(inspection.repackDir.path)")
        print("duration:    \(Fmt.duration(inspection.duration))")
        print("components:  \(inspection.stats.components)")
        print("payload:     \(Fmt.count(inspection.stats.payloadFiles)) files, \(Fmt.size(inspection.stats.payloadBytes))")
        print("binaries:    \(inspection.stats.binaries) (\(inspection.stats.bit32Binaries) 32-bit)")
        print("scripts:     \(inspection.stats.scripts) (\(inspection.stats.highRiskScripts) high risk)")
        print("relocatable: \(inspection.stats.relocatableComponents)")
        print("os limits:   \(inspection.stats.osConstraints)")

        print("\nSTRUCTURE")
        printTree(inspection.root, depth: 0)

        print("\nISSUES (\(inspection.issues.count))")
        for issue in inspection.issues {
            print("  [\(issue.severity.label)] \(issue.title)")
            print("     \(issue.message)")
            if !issue.paths.isEmpty {
                print("     paths: \(issue.paths.prefix(5).joined(separator: ", "))")
            }
        }

        if !inspection.notes.isEmpty {
            print("\nNOTES")
            for note in inspection.notes.prefix(20) {
                print("  - \(note)")
            }
        }
        print("════════════════════════\n")
    }

    private static func printTree(_ node: PackageNode, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        var suffix: [String] = []
        if let size = node.size { suffix.append(Fmt.size(size)) }
        if node.is32Bit { suffix.append("32-BIT") }
        if node.risk == .high { suffix.append("HIGH-RISK") }
        if !node.architectures.isEmpty { suffix.append(node.architectures.joined(separator: "/")) }
        if let note = node.note { suffix.append(note) }
        print("\(indent)\(node.kind == .product ? "◆" : "•") \(node.name)  \(suffix.joined(separator: " · "))")
        for child in node.children {
            printTree(child, depth: depth + 1)
        }
        if node.hiddenCount > 0 {
            print("\(indent)  … \(node.hiddenCount) more")
        }
    }
}
