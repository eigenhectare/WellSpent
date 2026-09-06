import SwiftUI
import WellSpentWatchContracts

struct WatchProjectPickerView: View {
    let projects: [ProjectSnapshot]
    let recentProjectIDs: [UUID]
    let activeDestinationID: UUID?
    let connectivityState: WatchConnectivityState
    let pendingCount: Int
    let onSelect: (ProjectSnapshot, Int?) -> Void
    var requestedProjectID: UUID? = nil

    @State private var configuringProject: WatchConfiguringProject?
    @State private var showsSystemActionHelp = false

    private var orderedProjects: [ProjectSnapshot] {
        WatchProjectPickerModel.orderedProjects(
            projects,
            activeDestinationID: activeDestinationID,
            recentProjectIDs: recentProjectIDs
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                header

                ForEach(orderedProjects, id: \.id) { project in
                    WatchProjectCard(
                        project: project,
                        onOpen: { onSelect(project, nil) },
                        onConfigure: {
                            configuringProject = WatchConfiguringProject(project: project)
                        }
                    )
                }

                Text("Manage projects on iPhone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6)
                    .accessibilityLabel("Project management is available in WellSpent on iPhone")
                Button("Siri & Controls") { showsSystemActionHelp = true }
                    .frame(minHeight: 44)
                    .tint(WatchDesign.teal)
                    .accessibilityIdentifier("watch.system-actions.help")
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(WatchDesign.foreground)
        .background(WatchDesign.canvas)
        .accessibilityIdentifier("watch.project-picker.screen")
        .watchPrivateScreen()
        .onChange(of: requestedProjectID, initial: true) { _, id in
            if let project = projects.first(where: { $0.id == id }) {
                configuringProject = WatchConfiguringProject(project: project)
            }
        }
        .sheet(item: $configuringProject) { project in
            WatchGoalSetupView(project: project.project) { durationGoalSeconds in
                configuringProject = nil
                onSelect(project.project, durationGoalSeconds)
            }
            .watchAccessibilityPreviewEnvironment()
        }
        .sheet(isPresented: $showsSystemActionHelp) {
            WatchSystemActionsHelpView()
                .watchAccessibilityPreviewEnvironment()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Projects")
                    .font(.headline)
                Text("Choose what gets your time")
                    .font(.caption2)
                    .foregroundStyle(WatchDesign.muted)
            }
            Spacer(minLength: 4)
            if let badge = WatchSyncBadge(
                connectivityState: connectivityState,
                pendingCount: pendingCount
            ) {
                Label(badge.title, systemImage: badge.symbol)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(badge.color)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(badge.accessibilityLabel)
                    .accessibilityIdentifier("watch.sync-badge.\(badge.identifier)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }
}

private struct WatchConfiguringProject: Identifiable {
    let project: ProjectSnapshot
    var id: UUID { project.id }
}

private struct WatchProjectCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let project: ProjectSnapshot
    let onOpen: () -> Void
    let onConfigure: () -> Void

    var body: some View {
        cardLayout {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 5) {
                    projectTitle
                    Label("Open Timer", systemImage: "play.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WatchDesign.teal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.leading, 10)
                .padding(.vertical, 10)
                .padding(.trailing, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(project.name), available project, open timer")
            .accessibilityHint("Starts and saves an untimed timer immediately.")
            .accessibilityIdentifier("watch.project.open.\(project.id.uuidString)")

            Button(action: onConfigure) {
                VStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                        .accessibilityHidden(true)
                    Text("Options")
                        .font(.caption2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(WatchDesign.teal)
                .frame(minWidth: 44, maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 58)
                .frame(minHeight: 44, maxHeight: .infinity)
                .padding(.vertical, 8)
                .background(WatchDesign.teal.opacity(0.09))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Timer options for \(project.name)")
            .accessibilityHint("Choose an open timer or a time goal to start immediately.")
            .accessibilityIdentifier("watch.project.options.\(project.id.uuidString)")
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .watchPanel()
    }

    private var cardLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(spacing: 0))
    }

    private var projectTitle: some View {
        Text(verbatim: project.name)
            .privacySensitive()
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(WatchDesign.foreground)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WatchProjectGlyph: View {
    let project: ProjectSnapshot
    let accent: Color

    var body: some View {
        Group {
            if let symbol = project.symbolName, symbol.containsEmoji {
                Text(symbol)
                    .font(.title3)
            } else {
                Image(systemName: project.symbolName ?? "folder.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: 28, height: 28)
        .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityHidden(true)
    }
}

private struct WatchSyncBadge {
    let identifier: String
    let title: String
    let symbol: String
    let accessibilityLabel: String
    let color: Color

    init?(connectivityState: WatchConnectivityState, pendingCount: Int) {
        if pendingCount > 0 {
            identifier = "pending"
            title = String(localized: "Pending")
            symbol = "arrow.triangle.2.circlepath"
            accessibilityLabel = String(
                localized: "Pending sync, \(pendingCount) items. Cached projects remain available.",
                comment: "The string catalog supplies singular and plural item forms."
            )
            color = .orange
            return
        }
        switch connectivityState {
        case .activating:
            identifier = "starting"
            title = String(localized: "Starting")
            symbol = "ellipsis.circle"
            accessibilityLabel = String(localized: "Sync is starting. Cached projects remain available.")
            color = .secondary
        case .available(let reachable, _):
            guard !reachable else { return nil }
            identifier = "offline"
            title = String(localized: "Offline")
            symbol = "wifi.slash"
            accessibilityLabel = String(
                localized: "Offline. Cached projects remain available and new timers will sync later.")
            color = .yellow
        case .unavailable:
            identifier = "offline"
            title = String(localized: "Offline")
            symbol = "wifi.slash"
            accessibilityLabel = String(
                localized: "Sync unavailable. Cached projects remain available and new timers will sync later.")
            color = .yellow
        case .blocked:
            return nil
        }
    }
}

extension String {
    fileprivate var containsEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmojiPresentation }
    }
}

extension Color {
    static func watchProjectToken(_ token: String?) -> Color {
        switch token?.lowercased() {
        case "cyan", "teal": .cyan
        case "green": .green
        case "orange": .orange
        case "pink": .pink
        case "purple", "indigo": .purple
        case "red": .red
        case "yellow": .yellow
        default: .blue
        }
    }
}
