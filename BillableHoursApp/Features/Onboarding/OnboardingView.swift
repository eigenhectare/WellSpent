import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: BillableHoursAppModel
    let complete: () -> Void

    @State private var name = ""
    @State private var colorToken = "blue"
    @State private var emoji = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "timer.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)
                        Text("Track work when it happens")
                            .font(.largeTitle.bold())
                        Text("One tap starts a project. One timer can be active at a time.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    explanation(
                        title: "Time survives interruptions",
                        detail:
                            "Elapsed time is calculated from saved timestamps, so leaving the app does not reset it.",
                        systemImage: "clock.arrow.circlepath"
                    )
                    explanation(
                        title: "Private on the Lock Screen",
                        detail: "Project names are hidden there by default. You can opt in from Settings.",
                        systemImage: "lock.shield"
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Create your first project")
                            .font(.headline)
                        TextField("Project name", text: $name)
                            .textInputAutocapitalization(.words)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("onboarding-project-name")
                        ProjectEmojiField(emoji: $emoji)
                        ProjectColorPicker(selection: $colorToken)
                        Button("Create Project and Continue") {
                            if model.createProject(
                                name: name,
                                colorToken: colorToken,
                                emoji: emoji
                            ) {
                                complete()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || !ProjectEmojiPresentation.isValid(emoji)
                        )
                        .accessibilityIdentifier("onboarding-create-project")
                    }
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))

                    Button("Explore before creating a project", action: complete)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("dismiss-onboarding")
                }
                .padding()
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
        .accessibilityIdentifier("onboarding-screen")
    }

    private func explanation(title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ProjectColorPicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color").font(.subheadline.weight(.semibold))
            HStack(spacing: 14) {
                ForEach(ProjectPalette.tokens, id: \.self) { token in
                    Button {
                        selection = token
                    } label: {
                        ZStack {
                            Circle().fill(ProjectPalette.color(for: token))
                            if selection == token {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(token.capitalized) project color")
                    .accessibilityValue(selection == token ? "Selected" : "Not selected")
                }
            }
        }
    }
}
