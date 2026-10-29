import Foundation
import Darwin

enum PackageRPC {
    static func send(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else { return }
        print(text)
        fflush(stdout)
    }

    static func run() {
        do {
            guard let input = readLine(), let data = input.data(using: .utf8),
                  let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let operation = request["operation"] as? String,
                  let sourcePath = request["source"] as? String,
                  let workspacePath = request["workspace"] as? String else { throw PackagerError.buildFailed("Invalid request") }
            L10n.language = request["language"] as? String == "zh" ? .zhHans : .en
            let source = URL(fileURLWithPath: sourcePath)
            let root = URL(fileURLWithPath: workspacePath, isDirectory: true)
            let log: (String) -> Void = { send(["type": "log", "message": $0]) }
            let inspection = try PackageInspector.inspect(source: source, workRoot: root, log: log)
            if operation == "inspect" {
                send(["type": "result", "value": report(inspection)])
            } else if operation == "rebuild" {
                let supplied = request["options"] as? [String: Any] ?? [:]
                var options = RebuildOptions.defaults(for: inspection)
                options.removeVersionLimits = supplied["versionLimits"] as? Bool ?? options.removeVersionLimits
                options.removeRelocatable = supplied["relocatable"] as? Bool ?? options.removeRelocatable
                options.stripHighRiskScripts = supplied["scripts"] as? Bool ?? false
                options.repairInstallSizes = supplied["installSizes"] as? Bool ?? options.repairInstallSizes
                if let directory = supplied["outputDirectory"] as? String { options.outputDirectory = URL(fileURLWithPath: directory) }
                if let name = supplied["outputName"] as? String { options.outputName = name }
                let result = try PackageRebuilder.rebuild(source: source, inspection: inspection, options: options, log: log)
                send(["type": "result", "value": ["output": result.outputURL.path, "size": result.size, "duration": result.duration, "fixes": result.appliedFixCount, "removedScripts": result.removedScriptNames, "verified": result.verified, "warnings": result.warnings]])
            } else { throw PackagerError.buildFailed("Unknown operation") }
        } catch let error as PackagerError {
            var value: [String: Any] = ["type": "error", "message": error.localizedDescription]
            if case .privilegeRequired(let request) = error {
                value["authorization"] = ["command": request.command, "source": request.sourceURL.path, "destination": request.destinationURL.path, "size": request.size, "fixes": request.appliedFixCount]
            }
            send(value); exit(1)
        } catch { send(["type": "error", "message": error.localizedDescription]); exit(1) }
    }

    static func report(_ inspection: PackageInspection) -> [String: Any] {
        let stats = inspection.stats
        func node(_ value: PackageNode) -> [String: Any] {
            ["id": value.id, "name": value.name, "path": value.path, "kind": value.kind.rawValue, "architectures": value.architectures, "legacy": value.is32Bit, "risk": value.risk.rawValue, "size": value.size ?? 0, "note": value.note ?? "", "hiddenCount": value.hiddenCount, "children": value.children.map(node)]
        }
        func issue(_ value: PackageIssue) -> [String: Any] {
            ["id": value.id, "severity": value.severity.rawValue, "category": value.category.rawValue, "title": value.title, "message": value.message, "paths": value.paths, "fix": value.fix?.rawValue ?? ""]
        }
        return ["title": inspection.title, "source": inspection.sourceURL.path, "format": inspection.format.rawValue, "signature": inspection.signature, "duration": inspection.duration,
            "compatibility": inspection.compatibility,
            "stats": ["components": stats.components, "files": stats.payloadFiles, "bytes": stats.payloadBytes, "binaries": stats.binaries, "legacy": stats.bit32Binaries, "scripts": stats.scripts, "riskyScripts": stats.highRiskScripts, "relocatable": stats.relocatableComponents, "versionLimits": stats.osConstraints, "installSizes": stats.sizeMetadataIssues],
            "tree": node(inspection.root), "issues": inspection.issues.map(issue), "issuesZH": inspection.issuesZH.map(issue), "notes": inspection.notes,
            "components": inspection.components.map { ["identifier": $0.identifier, "path": $0.relativePath, "location": $0.installLocation, "files": $0.payloadFileCount, "bytes": $0.payloadBytes, "architectures": $0.declaredArch ?? ""] as [String: Any] }]
    }
}
