import SwiftUI
import AppKit

// MARK: - Workspace

enum Workspace {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Packager/Workspace", isDirectory: true)
    }()

    @discardableResult
    static func ensure() -> URL {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func cleanAll() {
        try? FileManager.default.removeItem(at: root)
        ensure()
    }
}

// MARK: - Project

enum ProjectPhase: Equatable {
    case inspecting
    case ready
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isInspecting: Bool {
        if case .inspecting = self { return true }
        return false
    }
}

enum BuildState {
    case idle
    case running(String)
    case success(BuildResult)
    case failure(String)
    case authorization(PrivilegeRequest)

    var isBusy: Bool {
        if case .running = self { return true }
        return false
    }

    var isRunningOrAuthorizing: Bool {
        switch self {
        case .running, .authorization: return true
        default: return false
        }
    }
}

enum DetailTab: String, CaseIterable {
    case structure
    case issues

    var title: String {
        switch self {
        case .structure: return T("Structure")
        case .issues: return T("Issues")
        }
    }

    var symbol: String {
        switch self {
        case .structure: return "square.stack.3d.up"
        case .issues: return "exclamationmark.triangle"
        }
    }
}

enum TreeFilter: String, CaseIterable {
    case all
    case binaries
    case scripts
    case warnings

    var title: String {
        switch self {
        case .all: return T("All")
        case .binaries: return T("Binaries")
        case .scripts: return T("Scripts")
        case .warnings: return T("Warnings")
        }
    }

    var symbol: String? {
        switch self {
        case .all: return nil
        case .binaries: return "gearshape.2"
        case .scripts: return "curlybraces"
        case .warnings: return "exclamationmark.triangle"
        }
    }
}

@MainActor
final class PackageProject: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    let workRoot: URL
    let sourceSize: Int64
    let isBundle: Bool
    let addedAt = Date()

    @Published var title: String
    @Published var phase: ProjectPhase = .inspecting
    @Published var inspection: PackageInspection?
    @Published var options: RebuildOptions
    @Published var selectedNodeID: String?
    @Published var expanded: Set<String> = []
    @Published var searchText: String = ""
    @Published var treeFilter: TreeFilter = .all
    @Published var tab: DetailTab = .structure
    @Published var log: [LogEntry] = []
    @Published var buildState: BuildState = .idle
    @Published var showActivity: Bool = false
    @Published var isCancelling = false

    private var inspectionTask: Task<Void, Never>?
    private var buildTask: Task<Void, Never>?

    init(sourceURL: URL, workRoot: URL) {
        self.sourceURL = sourceURL
        self.workRoot = workRoot
        self.title = sourceURL.deletingPathExtension().lastPathComponent
        self.isBundle = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        self.sourceSize = PackageProject.measure(sourceURL)
        var defaults = RebuildOptions()
        defaults.outputName = RebuildOptions.defaultName(for: sourceURL)
        self.options = defaults
    }

    static func measure(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .totalFileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if let total = values.totalFileSize { return Int64(total) }
        if let size = values.fileSize { return Int64(size) }
        return 0
    }

    var displayTitle: String {
        if let inspection { return inspection.title }
        return title
    }

    var subtitle: String {
        if let inspection {
            return P(L10n.t("%d component(s)", inspection.stats.components)) + " · " + Fmt.size(sourceSize)
        }
        return Fmt.size(sourceSize)
    }

    var issueCount: Int {
        inspection?.issues.filter { $0.severity != .info }.count ?? 0
    }

    var canRebuild: Bool {
        phase.isReady && !buildState.isRunningOrAuthorizing
    }

    var hasHighRiskScripts: Bool {
        (inspection?.stats.highRiskScripts ?? 0) > 0
    }

    // MARK: Inspection

    func startInspection() {
        inspectionTask?.cancel()
        phase = .inspecting
        log.removeAll()
        buildState = .idle
        appendLog(T("Reading %@", sourceURL.lastPathComponent), level: .command)
        appendLog(T("Workspace: %@", workRoot.path), level: .info)

        let source = sourceURL
        let root = workRoot
        inspectionTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) { () -> PackageInspection in
                    try PackageInspector.inspect(source: source, workRoot: root) { line in
                        Task { @MainActor [weak self] in
                            self?.appendLog(line, level: .info)
                        }
                    }
                }.value
                guard let self, !Task.isCancelled else { return }
                self.applyInspection(result)
            } catch {
                guard let self else { return }
                self.phase = .failed(error.localizedDescription)
                self.appendLog(error.localizedDescription, level: .error)
            }
        }
    }

    func retryInspection() {
        // Fresh workspace before a retry.
        try? FileManager.default.removeItem(at: workRoot)
        try? FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
        startInspection()
    }

    private func applyInspection(_ result: PackageInspection) {
        inspection = result
        title = result.title
        options = RebuildOptions.defaults(for: result)
        var expandedIDs = Set<String>()
        expandedIDs.insert(result.root.id)
        for child in result.root.children where child.kind == .component {
            expandedIDs.insert(child.id)
        }
        expanded = expandedIDs
        selectedNodeID = result.root.id
        phase = .ready
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--tab"), index + 1 < args.count, args[index + 1] == "issues" {
            tab = .issues
        }
        appendLog(
            T("Ready · %d components · %d binaries · %d payload files", result.stats.components, result.stats.binaries, result.stats.payloadFiles),
            level: .success
        )
        if result.stats.bit32Binaries > 0 {
            appendLog(T("%d legacy architecture slices detected", result.stats.bit32Binaries), level: .warning)
        }
        if !result.payloadExpanded {
            appendLog(T("Payload expansion was not available — binary detection is limited"), level: .warning)
        }
    }

    // MARK: Rebuild

    func rebuild() {
        guard let inspection, phase.isReady, !buildState.isRunningOrAuthorizing else { return }
        isCancelling = false
        buildState = .running(T("Preparing the workspace"))
        showActivity = true
        appendLog(T("Repackage requested"), level: .command)
        if options.removeVersionLimits { appendLog(T("Option · remove OS version limits"), level: .info) }
        if options.removeRelocatable { appendLog(T("Option · clear relocatable flags"), level: .info) }
        if options.stripHighRiskScripts { appendLog(T("Option · strip high-risk scripts"), level: .info) }

        let source = sourceURL
        let opts = options
        buildTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) { () -> BuildResult in
                    try PackageRebuilder.rebuild(source: source, inspection: inspection, options: opts) { line in
                        Task { @MainActor [weak self] in
                            self?.appendLog(line, level: .info)
                        }
                    }
                }.value
                guard let self else { return }
                self.buildState = .success(result)
                self.appendLog(T("Saved %@ · %@ · %@", result.outputURL.lastPathComponent, Fmt.size(result.size), Fmt.duration(result.duration)), level: .success)
                withAnimation(.snappy(duration: 0.2)) {
                    self.showActivity = false
                }
            } catch let error as PackagerError {
                guard let self else { return }
                if case .privilegeRequired(let request) = error {
                    self.buildState = .authorization(request)
                    self.appendLog(request.message, level: .warning)
                    withAnimation(.snappy(duration: 0.2)) { self.showActivity = false }
                    return
                }
                if self.isCancelling {
                    self.buildState = .idle
                    self.appendLog(T("Repackage canceled"), level: .warning)
                    return
                }
                self.buildState = .failure(error.localizedDescription)
                self.appendLog(error.localizedDescription, level: .error)
                withAnimation(.snappy(duration: 0.2)) { self.showActivity = false }
            } catch {
                guard let self else { return }
                self.buildState = .failure(error.localizedDescription)
                self.appendLog(error.localizedDescription, level: .error)
                withAnimation(.snappy(duration: 0.2)) { self.showActivity = false }
            }
        }
    }

    func authorizeAndFinish(_ request: PrivilegeRequest) {
        buildState = .running(T("Waiting for macOS authorization"))
        appendLog(T("Requesting administrator authorization"), level: .warning)
        Task { [weak self] in
            let result = await PrivilegeBroker.runAsAdministrator(request.command)
            guard let self else { return }
            if result.succeeded {
                let size = PackageRebuilder.fileSize(request.destinationURL)
                try? FileManager.default.removeItem(at: request.sourceURL)
                let build = BuildResult(
                    outputURL: request.destinationURL,
                    size: size > 0 ? size : request.size,
                    duration: request.duration,
                    appliedFixCount: request.appliedFixCount,
                    removedScriptNames: request.removedScriptNames,
                    verified: true
                )
                self.buildState = .success(build)
                self.appendLog(T("Authorized · saved %@", request.destinationURL.lastPathComponent), level: .success)
            } else {
                let message = result.stderr.isEmpty ? T("Authorization was canceled.") : result.stderr
                self.buildState = .failure(message)
                self.appendLog(message, level: .error)
            }
        }
    }

    func cancelBuild() {
        isCancelling = true
        Shell.cancelAll()
        buildTask?.cancel()
        appendLog(T("Cancel the current operation"), level: .warning)
    }

    func resetBuildState() {
        if !buildState.isRunningOrAuthorizing {
            buildState = .idle
        }
    }

    func cancelAllWork() {
        inspectionTask?.cancel()
        buildTask?.cancel()
        Shell.cancelAll()
    }

    // MARK: Output

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = T("Choose")
        panel.message = T("Choose where Packager should save the rebuilt installer.")
        panel.directoryURL = options.outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            options.outputDirectory = url
            appendLog(T("Output folder set to %@", url.path), level: .info)
        }
    }

    func revealOutput() {
        guard case .success(let result) = buildState else { return }
        NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
    }

    func revealSource() {
        NSWorkspace.shared.activateFileViewerSelecting([sourceURL])
    }

    func revealWorkspace() {
        NSWorkspace.shared.open(workRoot)
    }

    func reveal(path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([sourceURL])
        }
    }

    func cleanWorkspace() {
        guard !buildState.isRunningOrAuthorizing else { return }
        inspectionTask?.cancel()
        try? FileManager.default.removeItem(at: workRoot)
        try? FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
        appendLog(T("Workspace cleared"), level: .info)
        retryInspection()
    }

    // MARK: Tree

    func toggleExpansion(_ nodeID: String) {
        if expanded.contains(nodeID) {
            expanded.remove(nodeID)
        } else {
            expanded.insert(nodeID)
        }
    }

    func expandAll() {
        guard let inspection else { return }
        expanded = inspection.root.allExpandableIDs
    }

    func collapseAll() {
        guard let inspection else { return }
        expanded = [inspection.root.id]
    }

    func appendLog(_ text: String, level: LogLevel) {
        let entry = LogEntry(level: level, text: P(text))
        log.append(entry)
        if log.count > 400 {
            log.removeFirst(log.count - 400)
        }
        if case .running = buildState, level != .success {
            buildState = .running(text)
        }
    }
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    @Published var projects: [PackageProject] = []
    @Published var selectedProjectID: UUID?
    @Published var alertMessage: String?
    @Published var isDropTargeted = false

    let workspaceRoot: URL

    init() {
        workspaceRoot = Workspace.ensure()
        Workspace.cleanAll()
    }

    var selectedProject: PackageProject? {
        projects.first { $0.id == selectedProjectID }
    }

    func addPackages(from urls: [URL]) {
        let fm = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                alertMessage = T("That item no longer exists on disk.")
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard ext == "pkg" || ext == "mpkg" else {
                alertMessage = T("Packager works with .pkg and .mpkg installers. “%@” is not an installer package.", url.lastPathComponent)
                continue
            }
            let standardized = url.standardizedFileURL
            if let existing = projects.first(where: { $0.sourceURL.standardizedFileURL == standardized }) {
                selectedProjectID = existing.id
                continue
            }

            let folderName = "\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(8))"
            let workRoot = workspaceRoot.appendingPathComponent(folderName, isDirectory: true)
            try? fm.createDirectory(at: workRoot, withIntermediateDirectories: true)

            let project = PackageProject(sourceURL: url, workRoot: workRoot)
            projects.insert(project, at: 0)
            selectedProjectID = project.id
            project.startInspection()
        }
    }

    func remove(_ project: PackageProject) {
        project.cancelAllWork()
        try? FileManager.default.removeItem(at: project.workRoot)
        projects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id {
            selectedProjectID = projects.first?.id
        }
    }

    func openPackagePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = T("Inspect")
        panel.message = T("Choose a .pkg or .mpkg installer to inspect in the workspace.")
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        if panel.runModal() == .OK {
            addPackages(from: panel.urls)
        }
    }

    func cleanWorkspace() {
        for project in projects where !project.buildState.isRunningOrAuthorizing {
            try? FileManager.default.removeItem(at: project.workRoot)
        }
        Workspace.cleanAll()
    }

    func revealWorkspace() {
        NSWorkspace.shared.open(workspaceRoot)
    }

    func openDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if urls.isEmpty {
                self.alertMessage = T("Those items weren’t readable as files. Drop a .pkg or .mpkg instead.")
            } else {
                self.addPackages(from: urls)
            }
        }
        return true
    }
}
