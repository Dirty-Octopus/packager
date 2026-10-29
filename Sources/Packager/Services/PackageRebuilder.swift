import Foundation

enum PackageRebuilder {
    static func rebuild(
        source: URL,
        inspection: PackageInspection,
        options: RebuildOptions,
        log: @escaping (String) -> Void
    ) throws -> BuildResult {
        let started = Date()
        let fm = FileManager.default
        let repack = inspection.repackDir

        // 1. Always start from a fresh expansion so toggles are reversible.
        log(T("Re-expanding the original package in the workspace"))
        try? fm.removeItem(at: repack)
        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            try PackageExpansion.expand(source: source, destination: repack, log: log)
        } else {
            let expand = Shell.run("/usr/sbin/pkgutil", ["--expand", source.path, repack.path])
            guard expand.succeeded else {
                if expand.indicatesPermissionFailure {
                    throw PackagerError.permissionDenied(expand.firstErrorLine ?? "Permission denied while reading the package.")
                }
                throw PackagerError.buildFailed(expand.combined.isEmpty ? "Could not re-expand the package." : expand.combined)
            }
            log(T("Workspace expansion ready (%@)", Fmt.duration(expand.duration)))
        }

        var appliedFixes = 0

        // 2. Distribution: drop OS version gates.
        if options.removeVersionLimits {
            let distributionURL = repack.appendingPathComponent("Distribution")
            if fm.fileExists(atPath: distributionURL.path) {
                let removed = try sanitizeDistribution(at: distributionURL, log: log)
                if removed > 0 {
                    appliedFixes += 1
                    log(T("Removed %d system version constraint(s)", removed))
                } else {
                    log(T("Distribution has no removable version constraints"))
                }
            } else {
                log(T("No Distribution script in this package"))
            }
        }

        // 3. PackageInfo: relocatable + scripts.
        var removedScriptNames: [String] = []
        let riskyScripts = inspection.scripts.filter { $0.risk == .high }

        for component in inspection.components {
            let infoURL = repack
                .appendingPathComponent(component.relativePath)
                .appendingPathComponent("PackageInfo")
            guard var info = PackageInfoFile.read(infoURL) else { continue }

            if options.removeRelocatable, info.relocatable {
                if info.clearRelocatable() {
                    appliedFixes += 1
                    log(T("Cleared relocatable on %@", component.displayName))
                }
            }

            if options.stripHighRiskScripts {
                let scriptsForComponent = riskyScripts.filter { $0.componentRelativePath == component.relativePath }
                if !scriptsForComponent.isEmpty {
                    let names = Set(scriptsForComponent.map(\.name))
                    let removedKeys = info.removeScriptEntries(named: names)
                    for script in scriptsForComponent {
                        let fileURL = repack
                            .appendingPathComponent(component.relativePath)
                            .appendingPathComponent("Scripts")
                            .appendingPathComponent(script.name)
                        try? fm.removeItem(at: fileURL)
                        try? fm.removeItem(at: fileURL.deletingLastPathComponent().appendingPathComponent("._\(script.name)"))
                        removedScriptNames.append(script.name)
                        log(T("Stripped script %@ from %@", script.name, component.displayName))
                    }
                    if !removedKeys.isEmpty { appliedFixes += 1 }
                }
            }

            let scriptsDirectory = repack
                .appendingPathComponent(component.relativePath)
                .appendingPathComponent("Scripts", isDirectory: true)
            if let leftovers = try? fm.contentsOfDirectory(atPath: scriptsDirectory.path), leftovers.isEmpty {
                try? fm.removeItem(at: scriptsDirectory)
            }

            if info.isModified {
                try info.save()
            }
        }

        if options.repairInstallSizes {
            appliedFixes += try InstallSizeMetadata.repair(in: repack, log: log)
        }

        // 4. Flatten into a modern XAR archive.
        let staging = inspection.workRoot.appendingPathComponent("staging", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let desiredName = normalizedOutputName(options.outputName, fallbackSource: source)
        let stagedURL = staging.appendingPathComponent(desiredName)
        log(T("Repackaging as a flat XAR archive"))
        let flatten = Shell.run("/usr/sbin/pkgutil", ["--flatten", repack.path, stagedURL.path])
        guard flatten.succeeded else {
            if flatten.indicatesPermissionFailure {
                throw PackagerError.permissionDenied(flatten.firstErrorLine ?? "Permission denied while repackaging.")
            }
            throw PackagerError.buildFailed(flatten.combined.isEmpty ? "pkgutil --flatten failed." : flatten.combined)
        }
        guard fm.fileExists(atPath: stagedURL.path) else {
            throw PackagerError.buildFailed("pkgutil reported success but no archive was produced.")
        }
        guard FileMagic.isXAR(stagedURL) else {
            throw PackagerError.buildFailed("The repackaged product is not a XAR archive.")
        }
        let stagedSize = fileSize(stagedURL)
        log(T("Wrote %@ (%@)", desiredName, Fmt.size(stagedSize)))

        // 5. Validate that Installer can still read the product.
        log(T("Verifying the new archive"))
        let verifyDir = inspection.workRoot.appendingPathComponent("verify", isDirectory: true)
        try? fm.removeItem(at: verifyDir)
        let verify = Shell.run("/usr/sbin/pkgutil", ["--expand", stagedURL.path, verifyDir.path])
        guard verify.succeeded else {
            throw PackagerError.buildFailed("Verification failed: \(verify.firstErrorLine ?? "the new package could not be expanded.")")
        }
        for component in inspection.components {
            let infoURL = verifyDir.appendingPathComponent(component.relativePath).appendingPathComponent("PackageInfo")
            guard let info = PackageInfoFile.read(infoURL), info.identifier == component.identifier else {
                throw PackagerError.buildFailed("Verification failed: component metadata missing or changed: \(component.displayName)")
            }
        }
        var warnings: [String] = []
        if options.removeVersionLimits,
           let distribution = try? XMLDocument(contentsOf: verifyDir.appendingPathComponent("Distribution")),
           !VersionGates.gates(in: distribution).isEmpty {
            warnings.append("Mixed JavaScript checks remain; review in Full mode. / 混合 JavaScript 检查仍保留，请在完整模式复核。")
        }
        try? fm.removeItem(at: verifyDir)
        log(T("Archive verified"))

        // 6. Place the product in the user's folder.
        let outputDirectory = options.outputDirectory
        var isDirectoryFlag: ObjCBool = false
        if !fm.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectoryFlag) {
            do {
                try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            } catch {
                throw privilegeRequest(
                    source: stagedURL,
                    destination: outputDirectory.appendingPathComponent(desiredName),
                    directory: outputDirectory,
                    started: started,
                    appliedFixes: appliedFixes,
                    removedScripts: removedScriptNames,
                    message: T("Packager can’t write to %@. Authorize once to save the new package there.", outputDirectory.path)
                )
            }
        }

        let destination = uniqueDestination(in: outputDirectory, name: desiredName)

        do {
            try fm.moveItem(at: stagedURL, to: destination)
        } catch {
            if fm.fileExists(atPath: stagedURL.path) {
                throw privilegeRequest(
                    source: stagedURL,
                    destination: destination,
                    directory: outputDirectory,
                    started: started,
                    appliedFixes: appliedFixes,
                    removedScripts: removedScriptNames,
                    message: T("Saving to %@ requires administrator access.", outputDirectory.path)
                )
            }
            throw PackagerError.buildFailed(error.localizedDescription)
        }

        let finalSize = fileSize(destination)
        log(T("Saved %@", destination.lastPathComponent))
        try? fm.removeItem(at: staging)

        return BuildResult(
            outputURL: destination,
            size: finalSize,
            duration: Date().timeIntervalSince(started),
            appliedFixCount: appliedFixes,
            removedScriptNames: removedScriptNames,
            verified: true,
            warnings: warnings
        )
    }

    // MARK: Distribution

    @discardableResult
    static func sanitizeDistribution(at url: URL, log: (String) -> Void) throws -> Int {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return 0 }

        var removedCount = 0

        if let doc = try? XMLDocument(contentsOf: url, options: []) {
            var removals: [XMLNode] = []
            let versionGates = VersionGates.gates(in: doc)
            for gate in versionGates where gate.removable {
                gate.element.detach()
                removedCount += 1
                log("Removed JavaScript OS gate: \(gate.expression)")
            }
            for gate in versionGates where !gate.removable {
                log("Manual review required: mixed JavaScript check preserved: \(gate.expression)")
            }

            func visit(_ node: XMLNode) {
                if let element = node as? XMLElement {
                    let name = element.name ?? ""
                    if name == "allowed-os-versions" {
                        removals.append(element)
                        return
                    }
                    if name == "os-version" {
                        let hasMin = element.attribute(forName: "min") != nil
                        let hasMax = element.attribute(forName: "max") != nil
                        if hasMin || hasMax { removedCount += 1 }
                        if hasMin { element.removeAttribute(forName: "min") }
                        if hasMax { element.removeAttribute(forName: "max") }
                    }
                    if name == "installer-gui-script" {
                        if element.attribute(forName: "min-os-version") != nil || element.attribute(forName: "max-os-version") != nil { removedCount += 1 }
                        element.removeAttribute(forName: "min-os-version")
                        element.removeAttribute(forName: "max-os-version")
                    }
                }
                for child in node.children ?? [] {
                    visit(child)
                }
            }

            if let root = doc.rootElement() {
                visit(root)
            }
            for node in removals { node.detach() }

            if removedCount > 0 || !removals.isEmpty {
                do {
                    let updated = doc.xmlData(options: [.nodePrettyPrint])
                    try updated.write(to: url)
                    return removedCount + removals.count
                } catch {
                    log(T("Could not rewrite Distribution as XML: %@", error.localizedDescription))
                }
            } else {
                return 0
            }
        }

        // Regex fallback for Distributions that are not well-formed XML.
        var working = text
        let allowedPattern = try NSRegularExpression(
            pattern: "<allowed-os-versions\\b[^>]*>.*?</allowed-os-versions>|<allowed-os-versions\\b[^>]*/>",
            options: [.dotMatchesLineSeparators]
        )
        let matches = allowedPattern.matches(in: working, options: [], range: NSRange(location: 0, length: (working as NSString).length))
        removedCount += matches.count
        if !matches.isEmpty {
            working = allowedPattern.stringByReplacingMatches(
                in: working,
                options: [],
                range: NSRange(location: 0, length: (working as NSString).length),
                withTemplate: ""
            )
        }

        let tagPattern = try NSRegularExpression(pattern: "<os-version\\b([^>]*)>", options: [])
        let nsWorking = working as NSString
        let tagMatches = tagPattern.matches(in: working, options: [], range: NSRange(location: 0, length: nsWorking.length))
        if !tagMatches.isEmpty {
            let mutable = NSMutableString(string: working)
            for match in tagMatches.reversed() {
                var attributes = nsWorking.substring(with: match.range(at: 1))
                let hadConstraint = attributes.contains(" min=") || attributes.contains(" max=")
                attributes = attributes.replacingOccurrences(
                    of: "\\s+(min|max)=\"[^\"]*\"",
                    with: "",
                    options: .regularExpression
                )
                guard let fullRange = Range(match.range, in: working) else { continue }
                let tagRange = NSRange(fullRange, in: working)
                mutable.replaceCharacters(in: tagRange, with: "<os-version\(attributes)>")
                if hadConstraint { removedCount += 1 }
            }
            working = mutable as String
        }

        if working != text {
            try working.write(to: url, atomically: true, encoding: .utf8)
        }
        return removedCount
    }

    // MARK: Helpers

    static func normalizedOutputName(_ raw: String, fallbackSource: URL) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = RebuildOptions.defaultName(for: fallbackSource)
        }
        name = name.replacingOccurrences(of: "/", with: "-")
        if !name.lowercased().hasSuffix(".pkg") && !name.lowercased().hasSuffix(".mpkg") {
            name += ".pkg"
        }
        return name
    }

    static func uniqueDestination(in directory: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index).\(ext)")
            index += 1
        }
        return candidate
    }

    static func writePlist(_ plist: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize else { return 0 }
        return Int64(size)
    }

    private static func privilegeRequest(
        source: URL,
        destination: URL,
        directory: URL,
        started: Date,
        appliedFixes: Int,
        removedScripts: [String],
        message: String
    ) -> PackagerError {
        let command = [
            "/bin/mkdir -p \(PrivilegeBroker.shellQuote(directory.path))",
            "/usr/bin/ditto \(PrivilegeBroker.shellQuote(source.path)) \(PrivilegeBroker.shellQuote(destination.path))"
        ].joined(separator: " && ")

        return PackagerError.privilegeRequired(PrivilegeRequest(
            message: message,
            command: command,
            sourceURL: source,
            destinationURL: destination,
            size: fileSize(source),
            duration: Date().timeIntervalSince(started),
            appliedFixCount: appliedFixes,
            removedScriptNames: removedScripts
        ))
    }
}
