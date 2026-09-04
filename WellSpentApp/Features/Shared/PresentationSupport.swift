import SwiftUI

enum DurationPresentation {
    static func exact(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    static func accessibility(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        if seconds > 0 || parts.isEmpty {
            parts.append("\(seconds) second\(seconds == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }
}

enum ProjectPalette {
    static let tokens = ["blue", "teal", "green", "orange", "pink", "purple"]

    static func color(for token: String?) -> Color {
        switch token {
        case "teal": .teal
        case "green": .green
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        default: .blue
        }
    }
}

enum ProjectEmojiPresentation {
    static func isValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || (trimmed.count == 1
                && trimmed.unicodeScalars.contains(where: { $0.properties.isEmoji }))
    }
}

struct ProjectEmojiField: View {
    @Binding var emoji: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emoji (optional)")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                TextField("🙂", text: $emoji)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .frame(minHeight: 44)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Project emoji")
                    .accessibilityIdentifier("project-emoji")
                    .onChange(of: emoji) { _, newValue in
                        if newValue.count > 1 {
                            emoji = String(newValue.prefix(1))
                        }
                    }
                Text("Choose one emoji from the emoji keyboard, or leave it empty.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !ProjectEmojiPresentation.isValid(emoji) {
                Text("Enter one emoji.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("project-emoji-error")
            }
        }
    }
}

struct SessionTagPicker: View {
    let tags: [SessionTagSnapshot]
    @Binding var selectedTagIDs: Set<UUID>

    private let columns = [
        GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        if tags.isEmpty {
            Text("No tag choices are available. Add tags in Settings.")
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(tags) { tag in
                    let isSelected = selectedTagIDs.contains(tag.id)
                    Button {
                        if isSelected {
                            selectedTagIDs.remove(tag.id)
                        } else {
                            selectedTagIDs.insert(tag.id)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .accessibilityHidden(true)
                            Text(tag.name)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? .blue : .secondary)
                    .accessibilityLabel(tag.name)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityHint("Double tap to \(isSelected ? "remove" : "add") this session tag.")
                    .accessibilityIdentifier("session-tag-\(tag.id.uuidString)")
                }
            }
        }
    }
}

struct ProjectStatusLabel: View {
    let project: ProjectSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ProjectPalette.color(for: project.colorToken))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(project.displayName)
            if project.status == .archived {
                Text("Archived")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SessionFlagsView: View {
    let isActive: Bool
    let stateLabel: String?
    let overlaps: Bool

    init(isActive: Bool = false, stateLabel: String? = nil, overlaps: Bool) {
        self.isActive = isActive
        self.stateLabel = stateLabel
        self.overlaps = overlaps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let stateLabel {
                sessionFlag(
                    stateLabel,
                    systemImage: stateLabel == "Paused" ? "pause.circle.fill" : "timer"
                )
                .accessibilityIdentifier("active-session-marker")
            } else if isActive {
                sessionFlag("Active", systemImage: "timer")
                    .accessibilityIdentifier("active-session-marker")
            }
            if overlaps {
                sessionFlag(
                    "Overlap included",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .accessibilityIdentifier("overlap-marker")
            }
        }
        .font(.caption.weight(.semibold))
    }

    private func sessionFlag(_ title: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }
}
