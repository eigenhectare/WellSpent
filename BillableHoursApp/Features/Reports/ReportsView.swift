import SwiftUI

private enum ReportMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case project = "Project"

    var id: String { rawValue }
}

private struct ReportSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
            .listRowBackground(Color.clear)
    }
}

struct ReportsView: View {
    @ObservedObject var model: BillableHoursAppModel

    @State private var mode = ReportMode.day
    @State private var selectedDate = Date.now
    @State private var selectedProjectID: UUID?
    @State private var projectRangeStart = Date.now
    @State private var projectRangeEnd = Date.now

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Report", selection: $mode) {
                    ForEach(ReportMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .accessibilityIdentifier("report-mode")

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    switch mode {
                    case .day:
                        DayReportView(
                            model: model,
                            selectedDate: $selectedDate,
                            now: timeline.date
                        )
                    case .week:
                        WeekReportView(
                            model: model,
                            selectedDate: $selectedDate,
                            now: timeline.date
                        )
                    case .project:
                        ProjectReportView(
                            model: model,
                            selectedProjectID: $selectedProjectID,
                            rangeStart: $projectRangeStart,
                            rangeEnd: $projectRangeEnd,
                            now: timeline.date
                        )
                    }
                }
            }
            .navigationTitle("Reports")
            .onAppear {
                if selectedProjectID == nil {
                    selectedProjectID = model.projects.first?.id
                }
            }
        }
    }
}

private struct DayReportView: View {
    @ObservedObject var model: BillableHoursAppModel
    @Binding var selectedDate: Date
    let now: Date

    var body: some View {
        List {
            Section("Selected day") {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .accessibilityIdentifier("day-report-date")
            }

            if let selection {
                let segments = model.reportSegments(for: selection, now: now)
                reportSummary(
                    title: "Day total",
                    segments: segments,
                    selection: selection,
                    emptyMessage: "No billable time on this day"
                )

                if !segments.isEmpty {
                    projectGroups(segments)
                    Section("Chronological segments") {
                        ForEach(segments) { segment in
                            ReportSegmentNavigationRow(model: model, segment: segment)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("day-report")
    }

    private var selection: ReportSelection? {
        model.dayInterval(containing: selectedDate).map { ReportSelection(interval: $0) }
    }

    @ViewBuilder
    private func reportSummary(
        title: String,
        segments: [ReportSegment],
        selection: ReportSelection,
        emptyMessage: String
    ) -> some View {
        Section("Summary") {
            NavigationLink {
                ReportDrillDownView(model: model, selection: selection, title: title)
            } label: {
                LabeledContent(title, value: DurationPresentation.exact(model.reportTotal(segments)))
                    .monospacedDigit()
            }
            .accessibilityIdentifier("day-report-total")
            if segments.isEmpty {
                Text(emptyMessage).foregroundStyle(.secondary)
            } else if segments.contains(where: \.isActive) {
                Label("Includes provisional active time", systemImage: "timer")
                    .font(.footnote)
                    .foregroundStyle(.blue)
            }
            if segments.contains(where: \.overlapsAnotherSession) {
                Text("Overlapping records are both fully included, so a day total may exceed 24 hours.")
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private func projectGroups(_ segments: [ReportSegment]) -> some View {
        Section {
            ReportSectionHeader("By project")
            ForEach(model.segmentsByProject(segments).keys.sorted(by: projectOrder), id: \.self) { projectID in
                let projectSegments = model.segmentsByProject(segments)[projectID] ?? []
                let projectSelection = ReportSelection(
                    interval: selection!.interval,
                    projectID: projectID
                )
                NavigationLink {
                    ReportDrillDownView(
                        model: model,
                        selection: projectSelection,
                        title: model.project(id: projectID)?.name ?? "Project"
                    )
                } label: {
                    LabeledContent(
                        model.project(id: projectID)?.name ?? "Unknown Project",
                        value: DurationPresentation.exact(model.reportTotal(projectSegments))
                    )
                }
            }
        }
    }

    private func projectOrder(_ first: UUID, _ second: UUID) -> Bool {
        let firstName = model.project(id: first)?.name ?? ""
        let secondName = model.project(id: second)?.name ?? ""
        if firstName != secondName { return firstName.localizedStandardCompare(secondName) == .orderedAscending }
        return first.uuidString < second.uuidString
    }
}

private struct WeekReportView: View {
    @ObservedObject var model: BillableHoursAppModel
    @Binding var selectedDate: Date
    let now: Date

    var body: some View {
        List {
            Section("Selected week") {
                DatePicker("A date in the week", selection: $selectedDate, displayedComponents: .date)
                    .accessibilityIdentifier("week-report-date")
                if let interval = selection?.interval {
                    Text(
                        interval.start.formatted(.dateTime.year().month().day()) + " – "
                            + interval.end.addingTimeInterval(-1).formatted(
                                .dateTime.year().month().day()
                            )
                    )
                }
            }

            if let selection {
                let segments = model.reportSegments(for: selection, now: now)
                Section("Summary") {
                    NavigationLink {
                        ReportDrillDownView(model: model, selection: selection, title: "Week total")
                    } label: {
                        LabeledContent(
                            "Week total",
                            value: DurationPresentation.exact(model.reportTotal(segments))
                        )
                    }
                    .accessibilityIdentifier("week-report-total")
                    if segments.isEmpty {
                        Text("No billable time in this locale-aware calendar week.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !segments.isEmpty {
                    Section {
                        ReportSectionHeader("By day")
                        ForEach(model.segmentsByDay(segments).keys.sorted(), id: \.self) { day in
                            let daySegments = model.segmentsByDay(segments)[day] ?? []
                            if let dayInterval = model.dayInterval(containing: day),
                                let clippedInterval = intersection(dayInterval, selection.interval)
                            {
                                NavigationLink {
                                    ReportDrillDownView(
                                        model: model,
                                        selection: ReportSelection(interval: clippedInterval),
                                        title: day.formatted(.dateTime.weekday(.wide).month().day())
                                    )
                                } label: {
                                    LabeledContent(
                                        day.formatted(.dateTime.weekday(.abbreviated).month().day()),
                                        value: DurationPresentation.exact(model.reportTotal(daySegments))
                                    )
                                }
                            }
                        }
                    }

                    Section {
                        ReportSectionHeader("By project")
                        ForEach(model.segmentsByProject(segments).keys.sorted(by: projectOrder), id: \.self) {
                            projectID in
                            let projectSegments = model.segmentsByProject(segments)[projectID] ?? []
                            NavigationLink {
                                ReportDrillDownView(
                                    model: model,
                                    selection: ReportSelection(
                                        interval: selection.interval,
                                        projectID: projectID
                                    ),
                                    title: model.project(id: projectID)?.name ?? "Project"
                                )
                            } label: {
                                LabeledContent(
                                    model.project(id: projectID)?.name ?? "Unknown Project",
                                    value: DurationPresentation.exact(model.reportTotal(projectSegments))
                                )
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("week-report")
    }

    private var selection: ReportSelection? {
        model.weekInterval(containing: selectedDate).map { ReportSelection(interval: $0) }
    }

    private func intersection(_ first: DateInterval, _ second: DateInterval) -> DateInterval? {
        let start = max(first.start, second.start)
        let end = min(first.end, second.end)
        return end > start ? DateInterval(start: start, end: end) : nil
    }

    private func projectOrder(_ first: UUID, _ second: UUID) -> Bool {
        let firstName = model.project(id: first)?.name ?? ""
        let secondName = model.project(id: second)?.name ?? ""
        if firstName != secondName { return firstName.localizedStandardCompare(secondName) == .orderedAscending }
        return first.uuidString < second.uuidString
    }
}

private struct ProjectReportView: View {
    @ObservedObject var model: BillableHoursAppModel
    @Binding var selectedProjectID: UUID?
    @Binding var rangeStart: Date
    @Binding var rangeEnd: Date
    let now: Date

    var body: some View {
        List {
            Section("Project and date range") {
                if model.projects.isEmpty {
                    Text("Create a project to use this report.")
                        .foregroundStyle(.secondary)
                } else {
                    Menu {
                        ForEach(model.projects) { project in
                            Button(projectDisplayName(project)) {
                                selectedProjectID = project.id
                            }
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Project")
                                    .foregroundStyle(.primary)
                                Text(selectedProjectDisplayName)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Project")
                    .accessibilityValue(selectedProjectDisplayName)
                    .accessibilityIdentifier("project-report-project")
                    .tint(.primary)
                }
                DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                DatePicker("Through", selection: $rangeEnd, displayedComponents: .date)
            }

            if rangeEnd < rangeStart {
                Section {
                    Label("The end date must be on or after the start date.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } else if let selection, let projectID = selectedProjectID {
                let segments = model.reportSegments(for: selection, now: now)
                Section("Summary") {
                    NavigationLink {
                        ReportDrillDownView(
                            model: model,
                            selection: selection,
                            title: model.project(id: projectID)?.name ?? "Project"
                        )
                    } label: {
                        LabeledContent(
                            "Exact total",
                            value: DurationPresentation.exact(model.reportTotal(segments))
                        )
                    }
                    .accessibilityIdentifier("project-report-total")
                    if let project = model.project(id: projectID), project.status == .archived {
                        Label("Archived project", systemImage: "archivebox")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if segments.isEmpty {
                        Text("No contributing sessions in this range.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !segments.isEmpty {
                    Section {
                        ReportSectionHeader("Contributing segments")
                        ForEach(segments) { segment in
                            ReportSegmentNavigationRow(model: model, segment: segment)
                        }
                    }
                }
            }
        }
        .onChange(of: model.projects.count) {
            if selectedProjectID.flatMap({ model.project(id: $0) }) == nil {
                selectedProjectID = model.projects.first?.id
            }
        }
        .accessibilityIdentifier("project-report")
    }

    private var selection: ReportSelection? {
        guard let projectID = selectedProjectID else { return nil }
        return model.inclusiveDayRange(from: rangeStart, through: rangeEnd).map {
            ReportSelection(interval: $0, projectID: projectID)
        }
    }

    private var selectedProjectDisplayName: String {
        guard let selectedProjectID,
            let project = model.project(id: selectedProjectID)
        else {
            return "Choose a project"
        }
        return projectDisplayName(project)
    }

    private func projectDisplayName(_ project: ProjectSnapshot) -> String {
        project.status == .archived
            ? "\(project.displayName) — Archived"
            : project.displayName
    }
}

struct ReportDrillDownView: View {
    @ObservedObject var model: BillableHoursAppModel
    let selection: ReportSelection
    let title: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let segments = model.reportSegments(for: selection, now: timeline.date)
            List {
                Section("Exact contributing total") {
                    LabeledContent(
                        "Sum of segments",
                        value: DurationPresentation.exact(model.reportTotal(segments))
                    )
                    .monospacedDigit()
                    Text("No rounding, deduplication, clamping, or hidden adjustment is applied.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Source-linked segments") {
                    if segments.isEmpty {
                        Text("No contributing sessions remain.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(segments) { segment in
                        ReportSegmentNavigationRow(model: model, segment: segment)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("report-drill-down")
    }
}

struct ReportSegmentNavigationRow: View {
    @ObservedObject var model: BillableHoursAppModel
    let segment: ReportSegment

    var body: some View {
        NavigationLink {
            SessionReviewView(model: model, sessionID: segment.sessionID)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.project(id: segment.projectID)?.name ?? "Unknown Project")
                    .font(.headline)
                Text(
                    segment.startAt.formatted(.dateTime.month().day().hour().minute().second())
                        + " – "
                        + segment.endAt.formatted(.dateTime.hour().minute().second())
                )
                Text(DurationPresentation.exact(segment.duration))
                    .font(.subheadline.monospacedDigit())
                if let note = segment.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                SessionFlagsView(
                    isActive: segment.isActive,
                    overlaps: segment.overlapsAnotherSession
                )
            }
            .padding(.vertical, 3)
        }
        .accessibilityIdentifier("report-source-session-\(segment.sessionID.uuidString)")
    }
}
