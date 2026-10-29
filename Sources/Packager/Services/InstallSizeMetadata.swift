import Foundation

/// Script-only packages may carry their files under Scripts/payload. Their native
/// payload is legitimately empty; only the Distribution size estimates need repair.
enum InstallSizeMetadata {
    struct Entry {
        let node: XMLElement
        let identifier: String
        let declared: Int
        let measured: Int
    }

    static func entries(in root: URL) -> (XMLDocument?, [Entry]) {
        guard let doc = try? XMLDocument(contentsOf: root.appendingPathComponent("Distribution"), options: []) else { return (nil, []) }
        let refs = ((try? doc.nodes(forXPath: "//pkg-ref")) ?? []).compactMap { $0 as? XMLElement }
        let entries = refs.compactMap { ref -> Entry? in
            guard let raw = ref.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                  let id = ref.attribute(forName: "id")?.stringValue else { return nil }
            let path = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
            guard !path.hasPrefix("/"), !path.contains(":") && !path.split(separator: "/").contains("..") else { return nil }
            let directory = root.appendingPathComponent(path)
            let scriptPayload = directory.appendingPathComponent("Scripts/payload")
            let bytes = directoryBytes(scriptPayload)
            let info = PackageInfoFile.read(directory.appendingPathComponent("PackageInfo"))
            let measured = bytes > 0 ? Int((bytes + 1023) / 1024) : (info?.payloadKBytes ?? 0)
            let declared = Int(ref.attribute(forName: "installKBytes")?.stringValue ?? "0") ?? 0
            guard measured > 0, declared == 0 else { return nil }
            return Entry(node: ref, identifier: id, declared: declared, measured: measured)
        }
        return (doc, entries)
    }

    static func issues(in root: URL) -> [PackageIssue] {
        let (_, entries) = entries(in: root)
        guard !entries.isEmpty else { return [] }
        return [PackageIssue(id: "install-sizes", severity: .warning, category: .integrity,
            title: "Zero installation sizes / 安装尺寸为零",
            message: "\(entries.count) component(s) contain files but declare 0 KB. Repair Distribution estimates; preserve the install scripts. / \(entries.count) 个组件含有文件却显示 0 KB，可修复尺寸元数据，保留安装脚本。",
            paths: entries.map(\.identifier), fix: .installSizes)]
    }

    static func repair(in root: URL, log: (String) -> Void) throws -> Int {
        let (doc, entries) = entries(in: root)
        guard let doc, !entries.isEmpty else { return 0 }
        for entry in entries {
            for name in ["installKBytes", "updateKBytes"] {
                entry.node.removeAttribute(forName: name)
                entry.node.addAttribute(XMLNode.attribute(withName: name, stringValue: String(entry.measured)) as! XMLNode)
            }
            log("Install size: \(entry.identifier) → \(entry.measured) KB")
        }
        try doc.xmlData(options: [.nodePrettyPrint]).write(to: root.appendingPathComponent("Distribution"), options: .atomic)
        return entries.count
    }

    static func directoryBytes(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let iterator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return 0 }
        return iterator.compactMap { $0 as? URL }.reduce(Int64(0)) { sum, file in
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), values.isRegularFile == true, values.isSymbolicLink != true else { return sum }
            return sum + Int64(values.fileSize ?? 0)
        }
    }
}
