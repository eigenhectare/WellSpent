import SwiftUI
import WellSpentWatchContracts

struct WatchEndedTimerSummaryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let run: TimerRunSnapshot
    let segments: [TimerSegmentSnapshot]
    let project: ProjectSnapshot?
    let tags: [TagSnapshot]
    let pendingSync: Bool
    let isReachable: Bool
    let isSaving: Bool
    let failure: WatchTimerAnnotationFailure?
    let onSave: (String, Set<UUID>) -> Void
    let onRetry: () -> Void
    let onDiscardFailure: () -> Void
    let onDone: () -> Void

    @State private var noteDraft: String
    @State private var selectedTagIDs: Set<UUID>
    @State private var editor: SummaryEditor?
    @State private var showsDiscardConfirmation = false

    init(
        run: TimerRunSnapshot,
        segments: [TimerSegmentSnapshot],
        project: ProjectSnapshot?,
        tags: [TagSnapshot],
        pendingSync: Bool,
        isReachable: Bool,
        isSaving: Bool,
        failure: WatchTimerAnnotationFailure?,
        onSave: @escaping (String, Set<UUID>) -> Void,
        onRetry: @escaping () -> Void,
        onDiscardFailure: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.run = run
        self.segments = segments
        self.project = project
        self.tags = tags
        self.pendingSync = pendingSync
        self.isReachable = isReachable
        self.isSaving = isSaving
        self.failure = failure
        self.onSave = onSave
        self.onRetry = onRetry
        self.onDiscardFailure = onDiscardFailure
        self.onDone = onDone
        _noteDraft = State(initialValue: run.normalizedNote ?? "")
        _selectedTagIDs = State(initialValue: Set(run.tagIDs))
    }

    private var metrics: WatchTimerMetrics {
        WatchTimerMetrics.calculate(
            run: run,
            segments: segments,
            at: run.endedAt ?? run.updatedAt
        )
    }

    private var draft: WatchTimerAnnotationDraft {
        WatchTimerAnnotationDraft(note: noteDraft, tagIDs: selectedTagIDs)
    }

    private var hasUnsavedChanges: Bool {
        draft.differs(from: run)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                savedHeader
                projectIdentity
                billableDuration
                detailRows
                syncLabel
                noteControl
                tagControl
                actions
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 9)
            .padding(.top, 5)
            .padding(.bottom, 9)
        }
        .scrollIndicators(.hidden)
        .background(Color.black)
        .accessibilityIdentifier("watch.end-summary.screen")
        .watchPrivateScreen(title: "Run saved", elapsedSeconds: metrics.billableSeconds)
        .sheet(item: $editor) { editor in
            Group {
                switch editor {
                case .note:
                    WatchSummaryNoteEditor(note: noteDraft) { noteDraft = $0 }
                case .tags:
                    WatchSummaryTagPicker(
                        availableTags: tags,
                        assignedTagIDs: selectedTagIDs
                    ) { selectedTagIDs = $0 }
                }
            }
            .watchAccessibilityPreviewEnvironment()
        }
        .alert(
            failure?.title ?? String(localized: "Couldn’t save changes"),
            isPresented: Binding(
                get: { failure != nil },
                set: {
                    if !$0 {
                        restoreSavedAnnotation()
                        onDiscardFailure()
                    }
                }
            )
        ) {
            Button("Try Again") { onRetry() }
            Button("Discard Edit", role: .destructive) {
                restoreSavedAnnotation()
                onDiscardFailure()
            }
        } message: {
            Text(failure?.message ?? String(localized: "Your run is still saved."))
        }
        .onChange(of: run.revision) {
            restoreSavedAnnotation()
        }
    }

    private var savedHeader: some View {
        Label("Saved", systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(.green)
            .accessibilityLabel("Run saved")
            .accessibilityIdentifier("watch.end-summary.saved")
    }

    private var projectIdentity: some View {
        Text(project?.name ?? String(localized: "Billable timer"))
            .privacySensitive()
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .multilineTextAlignment(.center)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
            .accessibilityLabel("Project, \(project?.name ?? String(localized: "Billable timer"))")
            .accessibilityIdentifier("watch.end-summary.project")
    }

    private var billableDuration: some View {
        VStack(spacing: 1) {
            Text(WatchDurationText.digital(metrics.billableSeconds))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.62)
                .lineLimit(1)
            Text("billable")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Billable duration, \(WatchDurationText.spoken(metrics.billableSeconds))"
        )
        .accessibilityIdentifier("watch.end-summary.billable")
    }

    private var detailRows: some View {
        VStack(spacing: 0) {
            WatchSummaryDetailRow(
                title: "Paused",
                value: WatchDurationText.digital(metrics.pausedSeconds),
                accessibilityValue: WatchDurationText.spoken(metrics.pausedSeconds),
                identifier: "paused"
            )
            Divider()
            WatchSummaryDetailRow(
                title: "Started",
                value: summaryDate(run.startedAt),
                accessibilityValue: accessibleDate(run.startedAt),
                identifier: "started"
            )
            Divider()
            WatchSummaryDetailRow(
                title: "Ended",
                value: summaryDate(run.endedAt ?? run.updatedAt),
                accessibilityValue: accessibleDate(run.endedAt ?? run.updatedAt),
                identifier: "ended"
            )
            if let goal = metrics.goal {
                Divider()
                WatchSummaryDetailRow(
                    title: "Goal",
                    value: goalText(goal),
                    accessibilityValue: goalAccessibilityText(goal),
                    identifier: "goal"
                )
            }
            Divider()
            WatchSummaryDetailRow(
                title: "Segments",
                value: "\(metrics.segmentCount)",
                accessibilityValue:
                    "\(metrics.segmentCount) segment\(metrics.segmentCount == 1 ? "" : "s")",
                identifier: "segments"
            )
        }
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
    }

    private var syncLabel: some View {
        Label {
            Text(syncTitle)
        } icon: {
            Image(systemName: syncSymbol)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(pendingSync ? (isReachable ? Color.orange : Color.yellow) : Color.green)
        .accessibilityLabel(syncAccessibilityLabel)
        .accessibilityIdentifier("watch.end-summary.sync")
    }

    private var noteControl: some View {
        Button {
            editor = .note
        } label: {
            WatchSummaryEditRow(
                symbol: "text.quote",
                title: "Note",
                value: draft.normalizedNote ?? String(localized: "Add optional note")
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(
            draft.normalizedNote.map { String(localized: "Note, \($0)") } ?? String(localized: "Note, none")
        )
        .accessibilityHint("Opens system text entry with dictation, Scribble, or keyboard.")
        .accessibilityIdentifier("watch.end-summary.note")
    }

    private var tagControl: some View {
        Button {
            editor = .tags
        } label: {
            WatchSummaryEditRow(
                symbol: "tag.fill",
                title: "Tags",
                value: tagSummary
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel("Tags, \(tagSummary)")
        .accessibilityHint("Select active tags or remove tags already assigned to this run.")
        .accessibilityIdentifier("watch.end-summary.tags")
    }

    @ViewBuilder
    private var actions: some View {
        if hasUnsavedChanges || isSaving {
            Button {
                onSave(noteDraft, selectedTagIDs)
            } label: {
                HStack(spacing: 7) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text(isSaving ? String(localized: "Saving…") : String(localized: "Save Changes"))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
            .accessibilityIdentifier(
                isSaving ? "watch.end-summary.saving" : "watch.end-summary.save"
            )
        }

        Button("Done") {
            if hasUnsavedChanges {
                showsDiscardConfirmation = true
            } else {
                onDone()
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(hasUnsavedChanges ? .gray : .blue)
        .controlSize(.large)
        .frame(minHeight: 44)
        .disabled(isSaving)
        .accessibilityHint(
            hasUnsavedChanges
                ? String(localized: "Asks before discarding the unsaved note or tag changes.")
                : String(localized: "Returns to the project picker. A note and tags are optional.")
        )
        .accessibilityIdentifier("watch.end-summary.done")
        .alert("Unsaved changes", isPresented: $showsDiscardConfirmation) {
            Button("Keep Editing", role: .cancel) {}
                .accessibilityIdentifier("watch.end-summary.keep-editing")
            Button("Discard Changes", role: .destructive) {
                restoreSavedAnnotation()
                onDone()
            }
            .accessibilityIdentifier("watch.end-summary.discard-unsaved")
        } message: {
            Text("The ended run stays saved. Only this unsaved note and tag edit will be discarded.")
        }
    }

    private var tagSummary: String {
        guard !selectedTagIDs.isEmpty else { return String(localized: "None") }
        let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        let names = selectedTagIDs.sorted { $0.uuidString < $1.uuidString }.map {
            tagsByID[$0] ?? String(localized: "Archived tag")
        }
        return names.joined(separator: ", ")
    }

    private var syncTitle: String {
        guard pendingSync else { return String(localized: "Synced") }
        return isReachable ? String(localized: "Pending sync") : String(localized: "Saved on Watch")
    }

    private var syncSymbol: String {
        guard pendingSync else { return "checkmark.circle" }
        return isReachable ? "arrow.up.arrow.down" : "wifi.slash"
    }

    private var syncAccessibilityLabel: String {
        guard pendingSync else { return String(localized: "Run synced") }
        return isReachable
            ? String(localized: "Run saved locally and pending sync")
            : String(localized: "Offline. Run saved locally and will sync later")
    }

    private func summaryDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func accessibleDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide).day().hour().minute().second())
    }

    private func goalText(_ goal: WatchTimerMetrics.Goal) -> String {
        if goal.isReached {
            guard goal.overtimeSeconds > 0 else { return String(localized: "Reached") }
            return "+\(WatchDurationText.digital(goal.overtimeSeconds))"
        }
        return "−\(WatchDurationText.digital(goal.remainingSeconds))"
    }

    private func goalAccessibilityText(_ goal: WatchTimerMetrics.Goal) -> String {
        if goal.isReached {
            guard goal.overtimeSeconds > 0 else { return String(localized: "Goal reached") }
            return String(localized: "Goal reached, \(WatchDurationText.spoken(goal.overtimeSeconds)) over")
        }
        return String(localized: "\(WatchDurationText.spoken(goal.remainingSeconds)) short of goal")
    }

    private func restoreSavedAnnotation() {
        noteDraft = run.normalizedNote ?? ""
        selectedTagIDs = Set(run.tagIDs)
    }
}

private enum SummaryEditor: String, Identifiable {
    case note
    case tags

    var id: String { rawValue }
}

private struct WatchSummaryDetailRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringResource
    let value: String
    let accessibilityValue: String
    let identifier: String

    var body: some View {
        rowLayout {
            Text(title)
                .foregroundStyle(.secondary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
            Text(value)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .monospacedDigit()
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
        .font(.caption)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(localized: title)), \(accessibilityValue)")
        .accessibilityIdentifier("watch.end-summary.\(identifier)")
    }

    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }
}

private struct WatchSummaryEditRow: View {
    let symbol: String
    let title: LocalizedStringResource
    let value: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(value)
                    .font(.caption2)
                    .privacySensitive()
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
        .contentShape(RoundedRectangle(cornerRadius: 15))
    }
}

private struct WatchSummaryNoteEditor: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var workingNote: String
    @WatchPrivacyRedaction private var hidesPrivateContent
    @FocusState private var isNoteFocused: Bool

    init(note: String, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        _workingNote = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("Note")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !hidesPrivateContent {
                        TextField("Optional note", text: $workingNote, axis: .vertical)
                            .focused($isNoteFocused)
                            .privacySensitive()
                            .lineLimit(3...8)
                            .textInputAutocapitalization(.sentences)
                            .accessibilityHint("Use dictation, Scribble, or the system keyboard.")
                            .accessibilityIdentifier("watch.end-summary.note-field")
                            .onChange(of: workingNote) {
                                if workingNote.count > WatchTimerAnnotationDraft.maximumNoteLength {
                                    workingNote = String(
                                        workingNote.prefix(
                                            WatchTimerAnnotationDraft.maximumNoteLength
                                        )
                                    )
                                }
                            }
                    }

                    Text(
                        verbatim:
                            "\(workingNote.count.formatted())/\(WatchTimerAnnotationDraft.maximumNoteLength.formatted())"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel(
                        "\(workingNote.count) of \(WatchTimerAnnotationDraft.maximumNoteLength) characters")

                    Button("Use Note") {
                        onSave(workingNote)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("watch.end-summary.note-use")

                    if !hidesPrivateContent && !workingNote.isEmpty {
                        // The system-entry field has a compact preview. Show
                        // the complete draft without moving Use Note below a
                        // potentially thousand-character scrolling passage.
                        Text(verbatim: workingNote)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .privacySensitive()
                            .accessibilityIdentifier("watch.end-summary.note-preview")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
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
                    .accessibilityIdentifier("watch.end-summary.note-cancel")
                }
            }
        }
        .accessibilityIdentifier("watch.end-summary.note-editor")
        .onChange(of: hidesPrivateContent) { _, hidden in
            if hidden { isNoteFocused = false }
        }
    }
}

private struct WatchSummaryTagPicker: View {
    let availableTags: [TagSnapshot]
    let historicalTagIDs: [UUID]
    let onSave: (Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID>
    @WatchPrivacyRedaction private var hidesPrivateContent

    init(
        availableTags: [TagSnapshot],
        assignedTagIDs: Set<UUID>,
        onSave: @escaping (Set<UUID>) -> Void
    ) {
        self.availableTags = availableTags
        let activeIDs = Set(availableTags.map(\.id))
        historicalTagIDs = assignedTagIDs.subtracting(activeIDs).sorted {
            $0.uuidString < $1.uuidString
        }
        self.onSave = onSave
        _selection = State(initialValue: assignedTagIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                Text("Tags")
                    .font(.headline)
                    .frame(minHeight: 28)
                    .fixedSize(horizontal: false, vertical: true)
                if availableTags.isEmpty && historicalTagIDs.isEmpty {
                    Text("No active tags. Create tags on iPhone, or save this run without one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("watch.end-summary.tags-empty")
                }

                ForEach(availableTags, id: \.id) { tag in
                    tagButton(id: tag.id, name: tag.name, isHistorical: false)
                }
                ForEach(Array(historicalTagIDs.enumerated()), id: \.element) { index, tagID in
                    tagButton(
                        id: tagID,
                        name: historicalTagIDs.count == 1
                            ? String(localized: "Archived tag")
                            : String(localized: "Archived tag \(index + 1)"),
                        isHistorical: true
                    )
                }

                Button("Use Selected Tags") {
                    onSave(selection)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("watch.end-summary.tags-use")
            }
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
                    .accessibilityIdentifier("watch.end-summary.tags-cancel")
                }
            }
        }
        .accessibilityIdentifier("watch.end-summary.tags-editor")
    }

    private func tagButton(id: UUID, name: String, isHistorical: Bool) -> some View {
        let isSelected = selection.contains(id)
        // Native List cells can expose their own accessibility nodes even
        // while a parent is hidden. Redact private labels at their source too.
        let displayName = hidesPrivateContent ? String(localized: "Tag") : name
        return Button {
            if isSelected {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .privacySensitive()
                        .fixedSize(horizontal: false, vertical: true)
                    if isHistorical {
                        Text("No longer active")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel(
            isSelected
                ? String(localized: "\(displayName), selected")
                : String(localized: "\(displayName), not selected")
        )
        .accessibilityHint(isSelected ? String(localized: "Removes this tag.") : String(localized: "Adds this tag."))
        .accessibilityHidden(hidesPrivateContent)
        .accessibilityIdentifier("watch.end-summary.tag.\(id.uuidString)")
    }
}
