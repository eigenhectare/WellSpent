import SwiftUI
import WellSpentWatchContracts

struct WatchGoalSetupView: View {
    let project: ProjectSnapshot?
    var currentGoalSeconds: Int? = nil
    var isEditing = false
    let onSelect: (Int?) -> Void

    @EnvironmentObject private var alerts: WatchGoalAlertCoordinator
    @Environment(\.dismiss) private var dismiss
    @WatchPrivacyRedaction private var hidesPrivateContent
    @State private var customMinutes = 45
    @State private var isChoosingCustomGoal = false

    private var recentCustomMinutes: [Int] {
        alerts.preferences.recentGoalSeconds.map { $0 / 60 }.filter { ![15, 30, 60].contains($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isChoosingCustomGoal {
                    VStack(spacing: 4) {
                        Text("Goal")
                            .font(.caption.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Picker("Minutes", selection: $customMinutes) {
                            ForEach(Array(stride(from: 5, through: 480, by: 5)), id: \.self) { minutes in
                                Text(
                                    Duration.seconds(minutes * 60).formatted(
                                        .units(allowed: [.minutes], width: .abbreviated))
                                )
                                .tag(minutes)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                        .frame(minHeight: 60, maxHeight: .infinity)
                        .accessibilityLabel("Goal minutes")
                        .accessibilityValue(Text(verbatim: "\(customMinutes)"))
                        .accessibilityIdentifier("watch.goal.custom-picker")
                        // A separate sibling, not a wheel overlay or a control
                        // trapped beneath a wheel inside a ScrollView.
                        Button("Use") { onSelect(customMinutes * 60) }
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Use \(customMinutes) minute goal")
                            .accessibilityIdentifier("watch.goal.custom-confirm")
                    }
                    .padding(.horizontal, 8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Time Goal")
                                .font(.headline)
                                .frame(minHeight: 28)
                                .fixedSize(horizontal: false, vertical: true)
                            Section {
                                Button {
                                    onSelect(nil)
                                } label: {
                                    Text(
                                        isEditing
                                            ? String(localized: "Remove Time Goal") : String(localized: "Open Timer")
                                    )
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityHint(
                                    isEditing
                                        ? String(localized: "Keeps tracking without a goal.")
                                        : String(localized: "Starts a timer with no time goal.")
                                )
                                .accessibilityIdentifier("watch.goal.open")
                                ForEach([15, 30, 60], id: \.self) { minutes in goalButton(minutes) }
                                Button {
                                    isChoosingCustomGoal = true
                                } label: {
                                    Text("Custom…").frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .accessibilityHint("Choose a time goal from 5 minutes to 8 hours.")
                                .accessibilityIdentifier("watch.goal.custom")
                            } header: {
                                Text(
                                    isEditing
                                        ? String(localized: "Update this run")
                                        : (hidesPrivateContent
                                            ? String(localized: "Start immediately")
                                            : project?.name ?? String(localized: "Start immediately"))
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .privacySensitive()
                            }
                            if !recentCustomMinutes.isEmpty {
                                Section {
                                    ForEach(recentCustomMinutes, id: \.self) { minutes in goalButton(minutes) }
                                } header: {
                                    Text("Recent goals").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Section {
                                Toggle(
                                    "Goal alerts",
                                    isOn: Binding(
                                        get: { alerts.preferences.alertsEnabled },
                                        set: { enabled in Task { await alerts.setEnabled(enabled) } }
                                    )
                                )
                                .frame(minHeight: 44)
                                .disabled(alerts.isRequestingPermission)
                                .accessibilityHint("Optional notification permission. Timers work without it.")
                                .accessibilityIdentifier("watch.goal.alerts-toggle")
                                Text(alerts.explanation)
                                    .font(.footnote)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("watch.goal.alerts-status")
                                if alerts.schedulingFailed {
                                    Button {
                                        alerts.refreshAuthorization()
                                    } label: {
                                        Text("Try Alert Again")
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .accessibilityIdentifier("watch.goal.alerts-retry")
                                }
                            } header: {
                                Text("On this Watch").font(.caption2).foregroundStyle(.secondary)
                            } footer: {
                                Text(
                                    "Project names follow your iPhone Lock Screen privacy setting after sync. A goal never ends a timer."
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                    }
                }
            }
            // Titles live in scrollable content so they do not truncate in the
            // small native navigation bar with large or expanded text.
            .watchPrivateScreen()
        }
        .containerBackground(.black, for: .navigation)
        .onAppear {
            if let seconds = currentGoalSeconds, (300...28_800).contains(seconds), seconds % 300 == 0 {
                customMinutes = seconds / 60
            }
        }
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
            }
        }
    }

    private func goalButton(_ minutes: Int) -> some View {
        Button {
            onSelect(minutes * 60)
        } label: {
            Text("\(minutes) min")
                .frame(maxWidth: .infinity, minHeight: 44)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel("\(minutes) minute time goal")
        .accessibilityHint(
            isEditing
                ? String(localized: "Saves this goal without changing counted time.")
                : String(localized: "Starts and saves a timer with this goal.")
        )
        .accessibilityIdentifier("watch.goal.\(minutes)")
    }
}
