import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var model: WellSpentAppModel
    @Environment(\.openURL) private var openURL
    @AppStorage(AppPreferenceKeys.showProjectNamesOnLockScreen)
    private var showProjectNamesOnLockScreen = false
    @State private var newTagName = ""
    @State private var tagRemovalCandidate: SessionTagSnapshot?
    @FocusState private var newTagFieldIsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "Show project names",
                        isOn: $showProjectNamesOnLockScreen
                    )
                    .accessibilityIdentifier("show-project-names-lock-screen")
                    .onChange(of: showProjectNamesOnLockScreen) { _, _ in
                        Task { await model.updateLiveActivityPrivacy() }
                    }

                    if showProjectNamesOnLockScreen {
                        HStack(alignment: .top) {
                            Image(systemName: "eye")
                                .accessibilityHidden(true)
                            Text(
                                "Live Activities may show confidential project names while your timer runs."
                            )
                            .accessibilityIdentifier("lock-screen-specific-preview")
                        }
                        .foregroundStyle(.primary)
                    } else {
                        HStack(alignment: .top) {
                            Image(systemName: "eye.slash")
                                .accessibilityHidden(true)
                            Text(
                                "Live Activities use the generic label “WellSpent timer.” Elapsed time and Stop remain visible."
                            )
                            .accessibilityIdentifier("lock-screen-private-preview")
                        }
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Lock Screen privacy")
                } footer: {
                    Text("The privacy-safe generic label is the default and persists after relaunch.")
                }

                Section("Time accuracy") {
                    LabeledContent("Precision", value: "Exact seconds")
                    Text("Durations come from saved start and end timestamps. Reports do not round or hide overlaps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Live Activity") {
                    LabeledContent(
                        "Status",
                        value: model.liveActivitiesEnabled ? "Available" : "Disabled"
                    )
                    .accessibilityIdentifier("live-activity-availability")

                    if !model.liveActivitiesEnabled {
                        Button("Open App Settings") {
                            guard let settingsURL = URL(string: UIApplication.openSettingsURLString)
                            else { return }
                            openURL(settingsURL)
                        }
                        .accessibilityIdentifier("open-live-activity-settings")
                    }
                }

                Section {
                    if model.availableSessionTags.isEmpty {
                        Text("No tag choices are available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.availableSessionTags) { tag in
                            HStack(spacing: 12) {
                                Text(tag.name)
                                Spacer()
                                Button(role: .destructive) {
                                    tagRemovalCandidate = tag
                                } label: {
                                    Label("Remove \(tag.name)", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .accessibilityLabel("Remove \(tag.name) tag")
                                .accessibilityIdentifier("remove-session-tag-\(tag.id.uuidString)")
                            }
                        }
                    }

                    TextField("New tag", text: $newTagName)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .focused($newTagFieldIsFocused)
                        .onSubmit(addTag)
                        .accessibilityIdentifier("new-session-tag")
                    Button("Add Tag", action: addTag)
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("add-session-tag")
                } header: {
                    Text("Session tags")
                } footer: {
                    Text(
                        "Removing a choice does not remove it from sessions that already use it. Re-enter its name to make it available again."
                    )
                }

                Section("Permissions") {
                    Text("This release does not request Calendar, notification, or iCloud permission.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Remove \(tagRemovalCandidate?.name ?? "tag")?",
                isPresented: Binding(
                    get: { tagRemovalCandidate != nil },
                    set: { if !$0 { tagRemovalCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Tag", role: .destructive) {
                    guard let tagRemovalCandidate else { return }
                    _ = model.removeSessionTag(id: tagRemovalCandidate.id)
                    self.tagRemovalCandidate = nil
                }
                Button("Cancel", role: .cancel) { tagRemovalCandidate = nil }
            } message: {
                Text("It will no longer be offered for new sessions. Historical sessions keep it.")
            }
        }
    }

    private func addTag() {
        if model.addSessionTag(name: newTagName) {
            newTagName = ""
            newTagFieldIsFocused = false
        }
    }
}
