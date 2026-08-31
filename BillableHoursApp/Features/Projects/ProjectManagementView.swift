import SwiftUI

struct ProjectManagementView: View {
    @ObservedObject var model: BillableHoursAppModel

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
            if model.activeSession?.projectID == project.id {
                Label("Timer active", systemImage: "timer")
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
    @ObservedObject var model: BillableHoursAppModel
    let mode: ProjectEditorMode

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorToken: String
    @State private var emoji: String

    init(model: BillableHoursAppModel, mode: ProjectEditorMode) {
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("project-name")
                    ProjectEmojiField(emoji: $emoji)
                    ProjectColorPicker(selection: $colorToken)
                }

                Section {
                    Text("Exact duplicate names are allowed, but the app will warn you after saving.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
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
