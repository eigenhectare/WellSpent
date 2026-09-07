import SwiftUI

struct ProjectManagementView: View {
    @ObservedObject var model: WellSpentAppModel

    @State private var editorMode: ProjectEditorMode?
    @State private var archiveCandidate: ProjectSnapshot?

    var body: some View {
        List {
            Section("Active projects") {
                if model.activeProjects.isEmpty {
                    Text("No active projects")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.activeProjects) { project in
                    projectRow(project)
                }
            }

            Section("Archived projects") {
                if model.archivedProjects.isEmpty {
                    Text("Archived projects stay available for reports and historical sessions.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.archivedProjects) { project in
                    HStack {
                        ProjectStatusLabel(project: project)
                        Spacer()
                        Button("Restore") {
                            _ = model.restoreProject(id: project.id)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("restore-project-\(project.id.uuidString)")
                    }
                }
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorMode = .create
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .accessibilityIdentifier("new-project")
            }
        }
        .sheet(item: $editorMode) { mode in
            ProjectEditorView(model: model, mode: mode)
        }
        .confirmationDialog(
            "Archive \(archiveCandidate?.displayName ?? "project")?",
            isPresented: Binding(
                get: { archiveCandidate != nil },
                set: { if !$0 { archiveCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                guard let archiveCandidate else { return }
                _ = model.archiveProject(id: archiveCandidate.id)
                self.archiveCandidate = nil
            }
            Button("Cancel", role: .cancel) { archiveCandidate = nil }
        } message: {
            Text("Its sessions remain visible in history and reports.")
        }
    }

    private func projectRow(_ project: ProjectSnapshot) -> some View {
        HStack {
            ProjectStatusLabel(project: project)
            if let activeRun = model.activeRun, activeRun.projectID == project.id {
                Label(
                    activeRun.state == .paused ? "Timer paused" : "Timer active",
                    systemImage: activeRun.state == .paused ? "pause.circle" : "timer"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .accessibilityIdentifier("active-project-archive-warning")
            }
            Spacer()
            Menu {
                Button("Edit", systemImage: "pencil") {
                    editorMode = .edit(project)
                }
                Button("Archive", systemImage: "archivebox", role: .destructive) {
                    archiveCandidate = project
                }
            } label: {
                Label("Manage \(project.displayName)", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityIdentifier("manage-project-\(project.id.uuidString)")
        }
    }
}

enum ProjectEditorMode: Identifiable {
    case create
    case edit(ProjectSnapshot)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let project): project.id.uuidString
        }
    }
}

struct ProjectEditorView: View {
    @ObservedObject var model: WellSpentAppModel
    let mode: ProjectEditorMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name: String
    @State private var colorToken: String
    @State private var emoji: String

    init(model: WellSpentAppModel, mode: ProjectEditorMode) {
        self.model = model
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _colorToken = State(initialValue: "blue")
            _emoji = State(initialValue: "")
        case .edit(let project):
            _name = State(initialValue: project.name)
            _colorToken = State(initialValue: project.colorToken ?? "blue")
            _emoji = State(initialValue: project.emoji ?? "")
        }
    }

    private var palette: WellSpentPalette { WellSpentPalette(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    projectPreview

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Project details")
                                .font(.headline)
                                .foregroundStyle(palette.ink)
                            Spacer()
                            Text(modeLabel)
                                .font(.caption)
                                .foregroundStyle(palette.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.subheadline.weight(.semibold))
                            TextField("Project name", text: $name)
                                .textInputAutocapitalization(.words)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 50)
                                .background(
                                    palette.background,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .accessibilityIdentifier("project-name")
                        }

                        Divider().overlay(palette.separator)
                        ProjectEmojiField(emoji: $emoji)
                        Divider().overlay(palette.separator)
                        ProjectColorPicker(selection: $colorToken)
                    }
                    .padding(18)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(palette.separator, lineWidth: 1)
                    }

                    Label(
                        "Exact duplicate names are allowed. WellSpent will warn you after saving.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(palette.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancel-project-editor")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if save() { dismiss() }
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !ProjectEmojiPresentation.isValid(emoji)
                    )
                    .accessibilityIdentifier("save-project")
                }
            }
        }
    }

    private var projectPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Preview", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                Spacer()
                Text("Ready to track")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
            }

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
        }
        .padding(18)
        .background(palette.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var modeLabel: String {
        switch mode {
        case .create: "New"
        case .edit: "Editing"
        }
    }

    private var title: String {
        switch mode {
        case .create: "New Project"
        case .edit: "Edit Project"
        }
    }

    private func save() -> Bool {
        switch mode {
        case .create:
            model.createProject(name: name, colorToken: colorToken, emoji: emoji)
        case .edit(let project):
            model.updateProject(
                id: project.id,
                name: name,
                colorToken: colorToken,
                emoji: emoji
            )
        }
    }
}
