import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: WellSpentAppModel
    let complete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var colorToken = "blue"
    @State private var emoji = ""

    private var palette: WellSpentPalette { WellSpentPalette(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to WellSpent")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(palette.ink)
                        Text("Track focused work with one tap.")
                            .font(.title3)
                            .foregroundStyle(palette.secondary)
                        Text(
                            "Start with a project for the client, contract, or kind of work you want to measure."
                        )
                        .font(.subheadline)
                        .foregroundStyle(palette.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("First project")
                                .font(.caption.weight(.semibold))
                                .textCase(.uppercase)
                                .tracking(0.8)
                                .foregroundStyle(palette.accent)
                            Spacer()
                            Text("Setup")
                                .font(.caption)
                                .foregroundStyle(palette.secondary)
                        }

                        projectPreview

                        TextField("Project name", text: $name)
                            .textInputAutocapitalization(.words)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 50)
                            .background(palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                        .tint(palette.accent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || !ProjectEmojiPresentation.isValid(emoji)
                        )
                        .accessibilityIdentifier("onboarding-create-project")
                    }
                    .padding(18)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(palette.separator, lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        explanation(
                            title: "Time survives interruptions",
                            detail: "Saved timestamps keep elapsed time accurate when you leave the app.",
                            systemImage: "clock.arrow.circlepath"
                        )
                        explanation(
                            title: "Private on the Lock Screen",
                            detail: "Project names stay hidden there unless you choose otherwise.",
                            systemImage: "lock.shield"
                        )
                        explanation(
                            title: "Apple Watch ready",
                            detail: "Open WellSpent on a paired Watch to track even while offline.",
                            systemImage: "applewatch"
                        )
                    }

                    Button("Explore before creating a project", action: complete)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(palette.accent)
                        .accessibilityIdentifier("dismiss-onboarding")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(palette.background)
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled()
        }
        .accessibilityIdentifier("onboarding-screen")
    }

    private var projectPreview: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(ProjectPalette.color(for: colorToken))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your project" : name)
                .font(.headline)
                .foregroundStyle(palette.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            if !emoji.isEmpty {
                Text(emoji)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }

    private func explanation(title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.ink)
                Text(detail).font(.footnote).foregroundStyle(palette.secondary)
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
            HStack(spacing: 4) {
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
                        .frame(width: 30, height: 30)
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(token.capitalized) project color")
                    .accessibilityValue(selection == token ? "Selected" : "Not selected")
                }
            }
        }
    }
}
