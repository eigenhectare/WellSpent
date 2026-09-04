import SwiftUI
import WellSpentWatchContracts

struct WatchTimerControlsView: View {
    let runState: TimerRunState
    let operation: WatchTimerControlOperation?
    let onEnd: () -> Void
    let onPauseOrResume: () -> Void
    let onNew: () -> Void

    private var isBusy: Bool { operation != nil }

    var body: some View {
        ViewThatFits(in: .vertical) {
            controls
            ScrollView { controls }
        }
        .background(Color.black)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Controls")
                    .font(.headline)
                    .accessibilityIdentifier("watch.controls.screen")
                Spacer()
                if let operation {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel(operation.progressTitle)
                        .accessibilityIdentifier("watch.controls.busy")
                }
            }
            .padding(.horizontal, 3)

            HStack(spacing: 8) {
                WatchTimerControlButton(
                    title: "End",
                    symbol: "xmark",
                    tint: Color(red: 0.62, green: 0.02, blue: 0.06),
                    accessibilityHint: "Asks for confirmation before ending and saving this run.",
                    identifier: "watch.controls.end",
                    isBusy: isBusy,
                    action: onEnd
                )

                WatchTimerControlButton(
                    title: runState == .paused ? "Resume" : "Pause",
                    symbol: runState == .paused ? "play.fill" : "pause.fill",
                    tint: runState == .paused ? .green : .orange,
                    accessibilityHint: runState == .paused
                        ? "Opens a new billable segment at one saved boundary."
                        : "Closes the current billable segment at one saved boundary.",
                    identifier: runState == .paused
                        ? "watch.controls.resume"
                        : "watch.controls.pause",
                    isBusy: isBusy,
                    action: onPauseOrResume
                )
            }

            WatchTimerControlButton(
                title: "New",
                symbol: "arrow.triangle.2.circlepath",
                tint: .blue,
                accessibilityHint:
                    "Choose a different project. The old run ends exactly when the new run starts.",
                identifier: "watch.controls.new",
                isBusy: isBusy,
                compact: true,
                action: onNew
            )

            Text(operation?.progressTitle ?? statusText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(operation == nil ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("watch.controls.status")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private var statusText: String {
        runState == .paused ? String(localized: "Run paused") : String(localized: "Run active")
    }
}

private struct WatchTimerControlButton: View {
    @WatchAccessibilitySettings private var accessibilitySettings
    let title: LocalizedStringResource
    let symbol: String
    let tint: Color
    let accessibilityHint: LocalizedStringResource
    let identifier: String
    let isBusy: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if compact {
                    HStack(spacing: 8) {
                        symbolView
                        Text(title)
                    }
                } else {
                    VStack(spacing: 6) {
                        symbolView
                        Text(title)
                    }
                }
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: compact ? 50 : 76)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.92), tint.opacity(0.58)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        .white.opacity(accessibilitySettings.increaseContrast ? 0.8 : 0.16),
                        lineWidth: accessibilitySettings.increaseContrast ? 1.5 : 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(accessibilityHint))
        .accessibilityIdentifier(identifier)
    }

    private var symbolView: some View {
        Image(systemName: symbol)
            .font(compact ? .body.weight(.bold) : .title3.weight(.bold))
            .accessibilityHidden(true)
    }
}

struct WatchSwitchProjectView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let projects: [ProjectSnapshot]
    let recentProjectIDs: [UUID]
    let currentProject: ProjectSnapshot?
    let isBusy: Bool
    let onSelect: (ProjectSnapshot) -> Void

    @Environment(\.dismiss) private var dismiss
    @WatchPrivacyRedaction private var hidesPrivateContent

    private var destinations: [ProjectSnapshot] {
        WatchProjectPickerModel.orderedProjects(
            projects,
            activeDestinationID: nil,
            recentProjectIDs: recentProjectIDs
        )
        .filter { $0.id != currentProject?.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    Text("New project")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(verbatim: currentProject?.name ?? WatchProjectIdentity.privateName)
                            .privacySensitive()
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("watch.switch.current")

                    if destinations.isEmpty {
                        ContentUnavailableView(
                            "No other projects",
                            systemImage: "folder",
                            description: Text("Create another project on iPhone, or keep this run active.")
                        )
                        .accessibilityIdentifier("watch.switch.empty")
                    } else {
                        ForEach(destinations, id: \.id) { project in
                            switchButton(project)
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .watchPrivateScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Cancel")
                    .disabled(hidesPrivateContent)
                    .accessibilityIdentifier("watch.switch.cancel")
                }
            }
        }
        .accessibilityIdentifier("watch.switch.screen")
    }

    private func switchButton(_ project: ProjectSnapshot) -> some View {
        let accent = Color.watchProjectToken(project.colorToken)
        return Button {
            onSelect(project)
        } label: {
            switchLayout {
                WatchProjectGlyph(project: project, accent: accent)
                Text(project.name)
                    .privacySensitive()
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
            .frame(minHeight: 52)
            .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Switch timer to \(project.name)")
        .accessibilityHint("Ends the current run and starts this project at one exact boundary.")
        .accessibilityIdentifier("watch.switch.project.\(project.id.uuidString)")
    }

    private var switchLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 9))
    }
}
