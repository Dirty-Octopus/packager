import Foundation
import AppKit
import Darwin

struct CommandResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var duration: TimeInterval
    var executable: String
    var arguments: [String]

    var succeeded: Bool { exitCode == 0 }

    var combined: String {
        [stdout, stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    var firstErrorLine: String? {
        let lines = stderr
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let line = lines.first(where: { $0.lowercased().contains("error") || $0.lowercased().contains("denied") }) {
            return line
        }
        return lines.first
    }

    var indicatesPermissionFailure: Bool {
        let haystack = (stderr + stdout).lowercased()
        return haystack.contains("permission denied")
            || haystack.contains("operation not permitted")
            || haystack.contains("not permitted")
            || haystack.contains("must be run as root")
            || haystack.contains("read-only file system")
    }
}

enum Shell {
    private static let lock = NSLock()
    private static var activeProcesses: [Process] = []

    static func cancelAll() {
        lock.lock()
        let processes = activeProcesses
        activeProcesses.removeAll()
        lock.unlock()
        for process in processes where process.isRunning {
            let pid = process.processIdentifier
            let group = getpgid(pid)
            if group == pid && group != getpgrp() { kill(-group, SIGTERM) }
            else { kill(pid, SIGTERM) }
        }
    }

    static func run(
        _ tool: String,
        _ arguments: [String],
        cwd: URL? = nil,
        environment: [String: String]? = nil
    ) -> CommandResult {
        let started = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()

        do {
            try process.run()
        } catch {
            return CommandResult(
                exitCode: -1,
                stdout: "",
                stderr: "Failed to launch \(tool): \(error.localizedDescription)",
                duration: Date().timeIntervalSince(started),
                executable: tool,
                arguments: arguments
            )
        }

        lock.lock()
        activeProcesses.append(process)
        lock.unlock()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        lock.lock()
        activeProcesses.removeAll { $0 === process }
        lock.unlock()

        let stdout = String(data: outData, encoding: .utf8)
            ?? String(data: outData, encoding: .isoLatin1)
            ?? ""
        let stderr = String(data: errData, encoding: .utf8)
            ?? String(data: errData, encoding: .isoLatin1)
            ?? ""

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: Date().timeIntervalSince(started),
            executable: tool,
            arguments: arguments
        )
    }

    static func runAsync(
        _ tool: String,
        _ arguments: [String],
        cwd: URL? = nil
    ) async -> CommandResult {
        await Task.detached(priority: .userInitiated) {
            run(tool, arguments, cwd: cwd)
        }.value
    }
}

// MARK: - Privilege broker

enum PrivilegeBroker {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func commandLine(_ tool: String, _ arguments: [String]) -> String {
        ([tool] + arguments).map(shellQuote).joined(separator: " ")
    }

    /// Runs a shell command through AppleScript's `administrator privileges`,
    /// which is what raises the native macOS authentication sheet.
    @MainActor
    static func runAsAdministrator(_ command: String) async -> CommandResult {
        let started = Date()
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            return CommandResult(
                exitCode: -1,
                stdout: "",
                stderr: "Could not create the authorization script.",
                duration: Date().timeIntervalSince(started),
                executable: "/bin/sh",
                arguments: ["-c", command]
            )
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Authorization canceled."
            return CommandResult(
                exitCode: -1,
                stdout: "",
                stderr: message,
                duration: Date().timeIntervalSince(started),
                executable: "/bin/sh",
                arguments: ["-c", command]
            )
        }
        return CommandResult(
            exitCode: 0,
            stdout: descriptor.stringValue ?? "",
            stderr: "",
            duration: Date().timeIntervalSince(started),
            executable: "/bin/sh",
            arguments: ["-c", command]
        )
    }
}
