import Foundation

/// Converts PackageMaker Contents/Archive.pax.gz bundles into the same expanded
/// pkgbuild layout as flat packages. Neither scripts nor payload executables run.
enum PackageExpansion {
    static func expand(source: URL, destination: URL, log: (String) -> Void) throws {
        let fm = FileManager.default
        let contents = source.appendingPathComponent("Contents")
        guard fm.fileExists(atPath: contents.path) else {
            try fm.copyItem(at: source, to: destination)
            return
        }
        let scratch = destination.deletingLastPathComponent().appendingPathComponent("legacy-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let distributionURL = contents.appendingPathComponent("distribution.dist")
        let distribution = try? XMLDocument(contentsOf: distributionURL, options: [])
        let packagesDirectory = contents.appendingPathComponent("Packages")
        let packages: [URL]
        if fm.fileExists(atPath: packagesDirectory.path) {
            packages = try fm.contentsOfDirectory(at: packagesDirectory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "pkg" }.sorted { $0.path < $1.path }
        } else { packages = [source] }
        guard !packages.isEmpty else { throw PackagerError.noComponents }

        for package in packages {
            let legacy = package.appendingPathComponent("Contents")
            let archive = legacy.appendingPathComponent("Archive.pax.gz")
            guard let data = try? Data(contentsOf: legacy.appendingPathComponent("Info.plist")),
                  let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let identifier = info["CFBundleIdentifier"] as? String,
                  fm.fileExists(atPath: archive.path) else {
                throw PackagerError.buildFailed("Unsupported legacy component: \(package.lastPathComponent)")
            }
            // Inspect archive member names first; tar also refuses escaping symlink writes.
            let listing = Shell.run("/usr/bin/tar", ["-tzf", archive.path])
            guard listing.succeeded else { throw PackagerError.expandFailed(listing.combined) }
            guard listing.stdout.split(separator: "\n").allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") }) else {
                throw PackagerError.expandFailed("Legacy archive contains a path outside the workspace")
            }
            let root = scratch.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let extract = Shell.run("/usr/bin/tar", ["-xzf", archive.path, "-C", root.path, "--no-same-owner"])
            guard extract.succeeded else { throw PackagerError.expandFailed(extract.combined) }
            let flat = scratch.appendingPathComponent(package.lastPathComponent)
            var arguments = ["--root", root.path, "--identifier", identifier, "--version", info["CFBundleShortVersionString"] as? String ?? "1.0", "--install-location", info["IFPkgFlagDefaultLocation"] as? String ?? "/"]
            let analyze = scratch.appendingPathComponent("components-\(UUID().uuidString).plist")
            let analysis = Shell.run("/usr/bin/pkgbuild", ["--analyze", "--root", root.path, analyze.path])
            if analysis.succeeded, let data = try? Data(contentsOf: analyze), var bundles = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] {
                for index in bundles.indices { bundles[index]["BundleIsRelocatable"] = (info["IFPkgFlagRelocatable"] as? Bool) ?? false }
                try PropertyListSerialization.data(fromPropertyList: bundles, format: .xml, options: 0).write(to: analyze)
                arguments += ["--component-plist", analyze.path]
            }
            let scripts = scratch.appendingPathComponent("scripts-\(UUID().uuidString)")
            for (old, modern) in [("preflight", "preinstall"), ("postflight", "postinstall"), ("preinstall", "preinstall"), ("postinstall", "postinstall")] {
                let script = legacy.appendingPathComponent("Resources/\(old)")
                if fm.fileExists(atPath: script.path) {
                    try fm.createDirectory(at: scripts, withIntermediateDirectories: true)
                    let target = scripts.appendingPathComponent(modern)
                    guard !fm.fileExists(atPath: target.path) else { throw PackagerError.buildFailed("Multiple legacy scripts require manual migration") }
                    try fm.copyItem(at: script, to: target)
                    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
                }
            }
            if fm.fileExists(atPath: scripts.path) { arguments += ["--scripts", scripts.path] }
            arguments.append(flat.path)
            log("Converting legacy component: \(package.lastPathComponent)")
            let build = Shell.run("/usr/bin/pkgbuild", arguments)
            guard build.succeeded else { throw PackagerError.buildFailed(build.combined) }
            let componentDestination = distribution == nil && packages.count == 1 ? destination : destination.appendingPathComponent(package.lastPathComponent)
            if componentDestination == destination { try fm.removeItem(at: destination) }
            let expand = Shell.run("/usr/sbin/pkgutil", ["--expand", flat.path, componentDestination.path])
            guard expand.succeeded else { throw PackagerError.expandFailed(expand.combined) }
        }

        if let distribution, let root = distribution.rootElement() {
            root.name = "installer-gui-script"
            root.removeAttribute(forName: "authoringTool")
            for node in (try? distribution.nodes(forXPath: "//pkg-ref")) ?? [] {
                guard let element = node as? XMLElement, let value = element.stringValue, value.contains("Contents/Packages/") else { continue }
                element.stringValue = "#" + (value as NSString).lastPathComponent
            }
            try distribution.xmlData(options: [.nodePrettyPrint]).write(to: destination.appendingPathComponent("Distribution"))
            let resources = contents.appendingPathComponent("Resources")
            if fm.fileExists(atPath: resources.path) { try fm.copyItem(at: resources, to: destination.appendingPathComponent("Resources")) }
        }
    }
}
