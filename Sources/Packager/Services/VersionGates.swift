import Foundation

/// Examines installer predicates as text. Package JavaScript is never executed.
/// Only predicates whose complete dependency set is an OS-version test can be removed.
enum VersionGates {
    struct Gate {
        let element: XMLElement
        let expression: String
        let removable: Bool
    }

    static func containsVersionLogic(_ text: String) -> Bool {
        text.range(of: #"\b(?:system\.version|os\.version|system\.compareVersions)\b"#, options: .regularExpression) != nil
    }

    static func gates(in document: XMLDocument) -> [Gate] {
        let scripts = ((try? document.nodes(forXPath: "//script")) ?? []).compactMap(\.stringValue).joined(separator: "\n")
        let functions = functionBodies(scripts)
        let checks = ((try? document.nodes(forXPath: "//installation-check | //volume-check")) ?? []).compactMap { $0 as? XMLElement }
        return checks.compactMap { element in
            guard let expression = element.attribute(forName: "script")?.stringValue else { return nil }
            let calls = identifiers(expression).filter { functions[$0] != nil }
            let bodies = calls.compactMap { functions[$0] }.joined(separator: "\n")
            guard containsVersionLogic(expression + bodies) else { return nil }
            let expanded = calls.reduce(expression) { value, name in
                value.replacingOccurrences(of: name + "()", with: functions[name] ?? "")
            }
            return Gate(element: element, expression: expression, removable: isVersionOnly(expanded))
        }
    }

    static func isVersionOnly(_ source: String) -> Bool {
        guard containsVersionLogic(maskLiteralsAndComments(source)) else { return false }
        var code = maskLiteralsAndComments(source)
        // Keep the complete predicate: a hardware/file/authorization check makes it non-removable.
        code = code.replacingOccurrences(of: #"\bsystem\.version(?:\.[A-Za-z_$][\w$]*)*|\bos\.version(?:\.[A-Za-z_$][\w$]*)*|\bsystem\.compareVersions\b|\bmy\.result\.(?:message|title|type)\b"#, with: " ", options: .regularExpression)
        let declarations = matches(#"\b(?:var|let|const)\s+([A-Za-z_$][\w$]*)"#, in: code).map { $0[1] }
        let allowed = Set(["var", "let", "const", "if", "else", "return", "true", "false", "null", "parseFloat", "parseInt", "Number"] + declarations)
        return identifiers(code).allSatisfy { allowed.contains($0) }
    }

    private static func functionBodies(_ source: String) -> [String: String] {
        let masked = maskLiteralsAndComments(source)
        let ns = source as NSString
        let mask = masked as NSString
        guard let regex = try? NSRegularExpression(pattern: #"\bfunction\s+([A-Za-z_$][\w$]*)\s*\(\s*\)\s*\{"#) else { return [:] }
        var result: [String: String] = [:]
        for match in regex.matches(in: masked, range: NSRange(location: 0, length: mask.length)) {
            var position = match.range.location + match.range.length
            let start = position
            var depth = 1
            while position < mask.length && depth > 0 {
                let character = mask.character(at: position)
                if character == 123 { depth += 1 }
                if character == 125 { depth -= 1 }
                position += 1
            }
            if depth == 0 {
                result[ns.substring(with: match.range(at: 1))] = ns.substring(with: NSRange(location: start, length: position - start - 1))
            }
        }
        return result
    }

    /// Preserve UTF-16 offsets for balanced brace scanning. Templates are deliberately
    /// unsupported: interpolated templates must not conceal non-version dependencies.
    static func maskLiteralsAndComments(_ source: String) -> String {
        let units = Array(source.utf16)
        var output = units
        var index = 0
        while index < units.count {
            let c = units[index]
            if c == 34 || c == 39 {
                let quote = c
                output[index] = 32; index += 1
                while index < units.count {
                    let current = units[index]; output[index] = 32; index += 1
                    if current == 92, index < units.count { output[index] = 32; index += 1 }
                    else if current == quote { break }
                }
            } else if c == 47, index + 1 < units.count, units[index + 1] == 47 {
                while index < units.count && units[index] != 10 { output[index] = 32; index += 1 }
            } else if c == 47, index + 1 < units.count, units[index + 1] == 42 {
                output[index] = 32; output[index + 1] = 32; index += 2
                while index < units.count {
                    if units[index] == 42, index + 1 < units.count, units[index + 1] == 47 {
                        output[index] = 32; output[index + 1] = 32; index += 2; break
                    }
                    output[index] = 32; index += 1
                }
            } else { index += 1 }
        }
        return String(decoding: output, as: UTF16.self)
    }

    private static func identifiers(_ text: String) -> [String] {
        matches(#"[A-Za-z_$][\w$]*"#, in: text).map { $0[0] }
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
        }
    }
}
