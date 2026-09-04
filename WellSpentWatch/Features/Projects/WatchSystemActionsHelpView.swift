import SwiftUI

struct WatchSystemActionsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Siri & Controls")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("watch.system-actions.title")
                    heading("Quick control")
                    Text(
                        "Add WellSpent Timer from the system Control Center gallery. Choose a favorite project in its configuration, or use your most recent project."
                    )
                    Text(
                        "The control starts a project, pauses a running timer, or resumes a paused timer. It opens WellSpent to save the change, including when your iPhone is offline."
                    )
                    heading("Siri & Shortcuts")
                    Text(
                        "Try “Pause my timer in WellSpent” or “Resume my timer in WellSpent.” Start, Switch Project, and End are also available in Shortcuts."
                    )
                    Text(
                        "System project choices follow the project-name privacy setting on iPhone. Siri availability and permission are managed in system settings; the app works without Siri."
                    )
                    heading("Action button")
                    Text(
                        "On supported Apple Watch Ultra models, assign the WellSpent control using the system Action button settings. WellSpent does not take over the button or use workout shortcuts."
                    )
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("watch.system-actions.done")
                }
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
    }

    private func heading(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}
