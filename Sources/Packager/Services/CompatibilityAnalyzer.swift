import Foundation

struct HostCapabilities {
    let architecture: String
    let macOS: String
    let rosetta: Bool

    static var current: HostCapabilities {
        let appleSilicon = Shell.run("/usr/sbin/sysctl", ["-n", "hw.optional.arm64"]).stdout == "1"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return HostCapabilities(architecture: appleSilicon ? "arm64" : "x86_64", macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            rosetta: FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime"))
    }
}

enum CompatibilityAnalyzer {
    enum Runtime: String { case native, translated, needsRosetta, partial, incompatible, unknown }

    static func runtime(architectures: [String], host: HostCapabilities) -> Runtime {
        if architectures.contains(host.architecture) { return .native }
        if host.architecture == "arm64", architectures.contains("x86_64") {
            guard (Int(host.macOS.split(separator: ".").first ?? "0") ?? 0) <= 27 else { return .incompatible }
            return host.rosetta ? .translated : .needsRosetta
        }
        return architectures.isEmpty || architectures.contains(where: { $0.hasPrefix("unknown-") }) ? .unknown : .incompatible
    }

    static func summarize(_ statuses: [Runtime], complete: Bool) -> Runtime {
        guard complete, !statuses.isEmpty else { return .unknown }
        if statuses.allSatisfy({ $0 == .incompatible }) { return .incompatible }
        if statuses.contains(.incompatible) || statuses.contains(.unknown) { return .partial }
        if statuses.contains(.needsRosetta) { return .needsRosetta }
        if statuses.contains(.translated) { return .translated }
        return .native
    }

    static func architecture(_ value: String) -> [String: Any] {
        let descriptions: [String: (String, Int)] = ["i386": ("Intel", 32), "x86_64": ("Intel", 64), "arm": ("ARM", 32), "arm64": ("ARM", 64), "arm64_32": ("ARM", 32), "ppc": ("PowerPC", 32), "ppc64": ("PowerPC", 64)]
        let info = descriptions[value]
        return ["name": value, "family": info?.0 ?? "Unknown", "bits": info?.1 ?? 0]
    }

    static func report(binaries: [BinaryInfo], components: [PackageComponent], complete: Bool, host: HostCapabilities) -> [String: Any] {
        let statuses = binaries.map { runtime(architectures: $0.architectures, host: host) }
        let architectures = Array(Set(binaries.flatMap(\.architectures))).sorted()
        return ["host": ["architecture": host.architecture, "macOS": host.macOS, "rosetta": host.rosetta],
                "runtime": summarize(statuses, complete: complete).rawValue,
                "native": statuses.filter { $0 == .native }.count,
                "translated": statuses.filter { $0 == .translated || $0 == .needsRosetta }.count,
                "unsupported": statuses.filter { $0 == .incompatible }.count,
                "architectures": architectures.map(architecture), "complete": complete,
                "components": components.map { component -> [String: Any] in
                    let matches = binaries.filter { component.relativePath.isEmpty || $0.relativePath.hasPrefix(component.relativePath + "/") }
                    let states = matches.map { runtime(architectures: $0.architectures, host: host) }
                    return ["name": component.displayName, "architectures": Array(Set(matches.flatMap(\.architectures))).sorted().map(architecture),
                            "runtime": summarize(states, complete: complete).rawValue]
                }]
    }
}
