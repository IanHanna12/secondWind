import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@main @MainActor
struct SecondWindMain {
    private static var window: NSWindow?

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)

        let runtime = SecondWindRuntime.local()
        let rootView = SecondWindApplicationView(runtime: runtime)
        let hostingView = NSHostingView(rootView: rootView)
        let window = makeWindow(contentView: hostingView)

        window.makeKeyAndOrderFront(nil)
        self.window = window
        application.activate(ignoringOtherApps: true)
        application.run()
    }

    private static func makeWindow(
        contentView: NSView
    ) -> NSWindow {
        let size = NSSize(width: 1120, height: 760)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Second Wind"
        window.minSize = NSSize(width: 920, height: 620)
        contentView.frame = NSRect(origin: .zero, size: size)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
        window.center()
        return window
    }
}

enum AuditExportFormat {
    case json
    case markdown
    case diagnostics

    var fileName: String {
        switch self {
        case .json: return "Second Wind Activity.json"
        case .markdown: return "Second Wind Activity.md"
        case .diagnostics: return "Second Wind Diagnostics.json"
        }
    }

    var contentType: UTType {
        self == .markdown ? .plainText : .json
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Home"
    case snapshots = "Storage overview"
    case inventoryInspector = "Inventory inspector"
    case architecture = "Architecture"
    case developerStorage = "Developer storage"
    case monitor = "System monitor"
    case cleanup = "Clean Up"
    case applications = "Applications"
    case rules = "Rules"
    case volumeCheck = "Volume check"
    case systemTasks = "System tasks"
    case about = "About"
    case activity = "Recovery & activity"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .snapshots:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .inventoryInspector: return "list.bullet.rectangle.portrait"
        case .architecture: return "point.3.connected.trianglepath.dotted"
        case .developerStorage: return "hammer"
        case .monitor: return "waveform.path.ecg"
        case .cleanup: return "sparkles"
        case .applications: return "app.dashed"
        case .rules: return "checklist"
        case .volumeCheck: return "externaldrive.badge.checkmark"
        case .systemTasks: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        case .activity: return "clock.arrow.circlepath"
        }
    }
}

private struct SecondWindApplicationView: View {
    @State private var model: SecondWindViewModel
    @State private var navigation = NavigationModel()

    init(runtime: SecondWindRuntime) {
        _model = State(
            initialValue: SecondWindViewModel(runtime: runtime)
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            selectedScreen
        }
        .alert(
            "Second Wind",
            isPresented: messageIsPresented
        ) {
            Button("OK") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
        .sheet(isPresented: cleanupReviewIsPresented) {
            CleanupPlanReviewSheet(model: model)
        }
        .sheet(isPresented: cleanupCompletionIsPresented) {
            if let completion = model.cleanupCompletion {
                CleanupCompletionSheet(completion: completion) {
                    navigation.section = .activity
                }
            }
        }
        .task {
            model.refreshDashboard()
            model.scan()
        }
        .frame(minWidth: 920, minHeight: 620)
    }

    private var sidebar: some View {
        List(selection: $navigation.section) {
            brand
            Section("OVERVIEW") {
                sidebarItem(.dashboard)
            }
            Section("MAKE SPACE") {
                sidebarItem(.cleanup)
                sidebarItem(.applications)
                sidebarItem(.rules)
            }
            Section("INSIGHTS") {
                sidebarItem(.snapshots)
                sidebarItem(.inventoryInspector)
                sidebarItem(.architecture)
                sidebarItem(.developerStorage)
                sidebarItem(.monitor)
                sidebarItem(.activity)
            }
            Section("SYSTEM") {
                sidebarItem(.volumeCheck)
                sidebarItem(.systemTasks)
                sidebarItem(.about)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Second Wind")
    }

    private var brand: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "wind.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Second Wind").font(.headline)
                    Text("Private Mac care")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var selectedScreen: some View {
        switch navigation.section ?? .dashboard {
        case .dashboard:
            DashboardScreen(model: model) {
                navigation.section = .cleanup
            }
        case .snapshots:
            StorageIntelligenceView(model: model)
        case .inventoryInspector:
            InventoryInspectorScreen(model: model)
        case .architecture:
            ArchitectureExplorerScreen()
        case .developerStorage:
            DeveloperStorageScreen(model: model)
        case .monitor:
            SystemMonitorScreen(model: model)
        case .cleanup:
            CleanupScreen(model: model)
        case .applications:
            ApplicationsScreen(model: model) {
                navigation.section = .cleanup
            }
        case .rules:
            RulesScreen(model: model)
        case .volumeCheck:
            VolumeCheckScreen(model: model)
        case .systemTasks:
            SystemTasksScreen(model: model)
        case .about:
            AboutScreen()
        case .activity:
            RecoveryActivityScreen(model: model)
        }
    }

    private var messageIsPresented: Binding<Bool> {
        Binding(
            get: { model.message != nil },
            set: { if !$0 { model.message = nil } }
        )
    }

    private var cleanupReviewIsPresented: Binding<Bool> {
        presentationBinding(for: .reviewingPlan)
    }

    private var cleanupCompletionIsPresented: Binding<Bool> {
        presentationBinding(for: .showingCompletion)
    }

    private func presentationBinding(
        for phase: CleanupPresentationPhase
    ) -> Binding<Bool> {
        Binding(
            get: { model.cleanupPresentation == phase },
            set: { isPresented in
                if !isPresented, model.cleanupPresentation == phase {
                    model.cleanupPresentation = .idle
                }
            }
        )
    }

    @ViewBuilder
    private func sidebarItem(
        _ section: AppSection
    ) -> some View {
        Label(section.rawValue, systemImage: section.symbol)
            .tag(section)
    }
}

@MainActor
@Observable
private final class NavigationModel {
    var section: AppSection? = .dashboard
}
