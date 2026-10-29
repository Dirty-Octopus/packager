import SwiftUI
import AppKit

@main
enum PackagerMain {
    static func main() {
        if CLIRunner.runIfRequested() {
            return
        }
        PackagerApp.main()
    }
}

struct PackagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        Window("Packager", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(settings)
                .environment(\.locale, settings.language.locale)
                .frame(minWidth: 1_080, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_240, height: 830)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(T("Open Package…")) {
                    model.openPackagePanel()
                }
                .keyboardShortcut("o")
            }

            CommandGroup(replacing: .appSettings) {
                Button(T("Settings…")) {
                    NotificationCenter.default.post(name: .packagerOpenSettings, object: nil)
                }
                .keyboardShortcut(",")
            }

            CommandMenu(T("Repackage")) {
                Button(T("Repackage")) {
                    model.selectedProject?.rebuild()
                }
                .keyboardShortcut("r")
                .disabled((model.selectedProject?.canRebuild ?? false) == false)

                Button(T("Reveal Output in Finder")) {
                    model.selectedProject?.revealOutput()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button(T("Reveal in Workspace")) {
                    model.selectedProject?.revealWorkspace()
                }

                Divider()

                Button(T("Clear Workspace")) {
                    model.cleanWorkspace()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let packagerOpenURLs = Notification.Name("packagerOpenURLs")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        if let saved = UserDefaults.standard.string(forKey: "packager.appearance"),
           let appearance = AppAppearance(rawValue: saved) {
            NSApp.appearance = appearance.appearance
        }

        if ProcessInfo.processInfo.environment["PACKAGER_APPEARANCE"] == "light" {
            NSApp.appearance = NSAppearance(named: .aqua)
        } else if ProcessInfo.processInfo.environment["PACKAGER_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }

        let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        let urls = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !urls.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NotificationCenter.default.post(name: .packagerOpenURLs, object: urls)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .packagerOpenURLs, object: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Shell.cancelAll()
        Workspace.cleanAll()
    }
}
