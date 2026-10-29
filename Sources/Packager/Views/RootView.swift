import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                workspace
                    .id(settings.language)
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: settings.hasCompletedOnboarding)
        .background(WindowAccessor())
        .onReceive(NotificationCenter.default.publisher(for: .packagerOpenSettings)) { _ in
            showSettings = true
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["PACKAGER_SHOW_SETTINGS"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showSettings = true
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
    }

    private var workspace: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()
                Rectangle()
                    .fill(Theme.stroke)
                    .frame(width: 1)
                content
            }

            if model.isDropTargeted {
                dropOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .background(AmbientBackground())
        .onReceive(NotificationCenter.default.publisher(for: .packagerOpenURLs)) { note in
            if let urls = note.object as? [URL] {
                model.addPackages(from: urls)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted) { providers in
            model.openDroppedItems(providers)
        }
        .alert("Packager", isPresented: alertBinding) {
            Button(T("OK")) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .animation(.snappy(duration: 0.22), value: model.selectedProjectID)
        .animation(.snappy(duration: 0.18), value: model.isDropTargeted)
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let project = model.selectedProject {
                ProjectView(project: project)
                    .id(project.id)
            } else {
                WelcomeView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                BrandMark(size: 54)
                Text(T("Drop to inspect"))
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(-0.3)
                Text(T("The package is unpacked in your workspace — nothing is installed."))
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.surface.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
            )
            .shadow(color: Theme.accent.opacity(0.18), radius: 30, y: 10)
        }
    }
}
