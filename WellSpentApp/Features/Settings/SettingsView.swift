import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var model: WellSpentAppModel
    @Environment(\.openURL) private var openURL
    @AppStorage(AppPreferenceKeys.showProjectNamesOnLockScreen)
    private var showProjectNamesOnLockScreen = false
    @State private var newTagName = ""
    @State private var tagRemovalCandidate: SessionTagSnapshot?
    @State private var showsDeleteAllDataConfirmation = false
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

                Section("Privacy") {
                    Text(
                        "WellSpent uses no account, server, analytics, tracking, or CloudKit sync. Activity data is excluded from device backups."
                    )
                    Text(
                        "This release does not request Calendar or notification access and does not export files."
                    )
                    .foregroundStyle(.secondary)

                    if let privacyPolicyURL = WellSpentExternalLinks.privacyPolicy {
                        Link(destination: privacyPolicyURL) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                        .accessibilityIdentifier("privacy-policy-link")
                    }
                }

                Section("Help and legal") {
                    if let supportURL = WellSpentExternalLinks.support {
                        Link(destination: supportURL) {
                            Label("Support", systemImage: "questionmark.circle")
                        }
                        .accessibilityIdentifier("support-link")
                    }

                    if let sourceCodeURL = WellSpentExternalLinks.sourceCode {
                        Link(destination: sourceCodeURL) {
                            Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .accessibilityIdentifier("source-code-link")
                    }

                    LabeledContent("Version", value: WellSpentExternalLinks.versionDescription)
                        .accessibilityIdentifier("app-version")
                    LabeledContent("Copyright", value: "© 2026 WellSpent contributors")
                        .accessibilityIdentifier("app-copyright")
                    Text("Source code is available under the GNU Affero General Public License v3.0.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("source-license")
                }

                Section("Local data") {
                    Button("Erase All WellSpent Data", role: .destructive) {
                        showsDeleteAllDataConfirmation = true
                    }
                    .disabled(model.isPerformingTimerCommand)
                    .accessibilityIdentifier("delete-all-local-data")

                    Text(
                        "Deletes projects, sessions, notes, custom tags, preferences, and pending Lock Screen actions from this iPhone."
                    )
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
            .confirmationDialog(
                "Delete all local data?",
                isPresented: $showsDeleteAllDataConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Data", role: .destructive) {
                    Task { await model.deleteAllLocalData() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This permanently deletes every project, session, note, custom tag, and preference. This action cannot be undone."
                )
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
