import Foundation

/// Reads the two PackageInfo dialects found in the wild:
/// 1. A property list dictionary (PackageMaker era).
/// 2. pkgbuild's `<pkg-info>` XML document.
struct PackageInfoFile {
    enum Kind {
        case plist
        case pkgInfoXML
    }

    var url: URL
    var kind: Kind
    var identifier: String
    var version: String
    var installLocation: String
    var relocatable: Bool
    var declaredArch: String?
    var scriptEntries: [(key: String, file: String)]
    var payloadFileCount: Int?
    var payloadKBytes: Int?
    var isModified = false

    private var plist: [String: Any]?
    private var document: XMLDocument?

    static func read(_ url: URL) -> PackageInfoFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        if let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let dictionary = object as? [String: Any] {
            var entries: [(String, String)] = []
            if let scripts = dictionary["scripts"] as? [String: Any] {
                for (key, value) in scripts {
                    if let file = value as? String {
                        entries.append((key, normalizeScriptFile(file)))
                    }
                }
            }
            let arch: String?
            if let value = dictionary["arch"] as? String {
                arch = value
            } else if let values = dictionary["arch"] as? [String] {
                arch = values.joined(separator: ", ")
            } else {
                arch = nil
            }
            return PackageInfoFile(
                url: url,
                kind: .plist,
                identifier: dictionary["identifier"] as? String ?? "",
                version: dictionary["version"] as? String ?? "—",
                installLocation: dictionary["install-location"] as? String ?? "/",
                relocatable: (dictionary["relocatable"] as? Bool) ?? false,
                declaredArch: arch,
                scriptEntries: entries.sorted { $0.0 < $1.0 },
                payloadFileCount: nil,
                payloadKBytes: nil,
                plist: dictionary
            )
        }

        if let document = try? XMLDocument(data: data, options: []),
           let root = document.rootElement(),
           root.name == "pkg-info" {
            var entries: [(String, String)] = []
            if let scripts = root.elements(forName: "scripts").first {
                for child in scripts.children ?? [] {
                    guard let element = child as? XMLElement,
                          let name = element.name,
                          let file = element.attribute(forName: "file")?.stringValue
                    else { continue }
                    entries.append((name, normalizeScriptFile(file)))
                }
            }
            let payload = root.elements(forName: "payload").first
            let fileCount = payload?.attribute(forName: "numberOfFiles")?.stringValue.flatMap(Int.init)
            let kBytes = payload?.attribute(forName: "installKBytes")?.stringValue.flatMap(Int.init)
            let relocatable = (root.attribute(forName: "relocatable")?.stringValue ?? "false").lowercased() == "true"
            return PackageInfoFile(
                url: url,
                kind: .pkgInfoXML,
                identifier: root.attribute(forName: "identifier")?.stringValue ?? "",
                version: root.attribute(forName: "version")?.stringValue ?? "—",
                installLocation: root.attribute(forName: "install-location")?.stringValue ?? "/",
                relocatable: relocatable,
                declaredArch: root.attribute(forName: "arch")?.stringValue,
                scriptEntries: entries.sorted { $0.0 < $1.0 },
                payloadFileCount: fileCount,
                payloadKBytes: kBytes,
                document: document
            )
        }

        return nil
    }

    mutating func clearRelocatable() -> Bool {
        switch kind {
        case .plist:
            guard var dictionary = plist else { return false }
            let hadValue = dictionary["relocatable"] != nil
            dictionary.removeValue(forKey: "relocatable")
            plist = dictionary
            relocatable = false
            isModified = isModified || hadValue
            return hadValue
        case .pkgInfoXML:
            guard let root = document?.rootElement() else { return false }
            let hadValue = relocatable
            root.removeAttribute(forName: "relocatable")
            relocatable = false
            isModified = true
            return hadValue
        }
    }

    /// Removes script entries by file name and returns the removed installer keys.
    mutating func removeScriptEntries(named names: Set<String>) -> [String] {
        var removed: [String] = []
        switch kind {
        case .plist:
            guard var dictionary = plist, var scripts = dictionary["scripts"] as? [String: Any] else { return [] }
            for (key, value) in scripts {
                if let file = value as? String, names.contains(normalizeScriptFile(file)) {
                    scripts.removeValue(forKey: key)
                    removed.append(key)
                }
            }
            if scripts.isEmpty {
                dictionary.removeValue(forKey: "scripts")
            } else {
                dictionary["scripts"] = scripts
            }
            plist = dictionary
            scriptEntries.removeAll { names.contains($0.file) }
            isModified = isModified || !removed.isEmpty
        case .pkgInfoXML:
            guard let root = document?.rootElement(),
                  let scripts = root.elements(forName: "scripts").first
            else { return [] }
            var toDetach: [XMLNode] = []
            for child in scripts.children ?? [] {
                guard let element = child as? XMLElement,
                      let file = element.attribute(forName: "file")?.stringValue,
                      names.contains(normalizeScriptFile(file))
                else { continue }
                removed.append(element.name ?? "script")
                toDetach.append(element)
            }
            for node in toDetach { node.detach() }
            let remaining = (scripts.children ?? []).compactMap { $0 as? XMLElement }
            if remaining.isEmpty {
                scripts.detach()
            }
            scriptEntries.removeAll { names.contains($0.file) }
            isModified = isModified || !removed.isEmpty
        }
        return removed
    }

    func save() throws {
        switch kind {
        case .plist:
            guard let plist else { return }
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        case .pkgInfoXML:
            guard let document else { return }
            let data = document.xmlData(options: [.nodePrettyPrint])
            try data.write(to: url, options: .atomic)
        }
    }

}

private func normalizeScriptFile(_ file: String) -> String {
    var cleaned = file
    while cleaned.hasPrefix("./") { cleaned.removeFirst(2) }
    return (cleaned as NSString).lastPathComponent
}
