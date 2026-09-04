#if DEBUG
    import Foundation
    import WellSpentWatchContracts
    import WellSpentWatchStore

    enum WatchUITestFixture: String {
        case active
        case activeNoGoal = "active-no-goal"
        case activeArchivedTarget = "active-archived-target"
        case activeOffline = "active-offline"
        case activePending = "active-pending"
        case activeSingleProject = "active-single-project"
        case archived
        case conflict
        case empty
        case ended
        case endedHistoricalTag = "ended-historical-tag"
        case endedLongContent = "ended-long-content"
        case endedOffline = "ended-offline"
        case goalReached = "goal-reached"
        case largeDuration = "large-duration"
        case longNames = "long-names"
        case offline
        case overtime
        case paused
        case pending
        case populated
        case setup
        case staleTotals = "stale-totals"
        case storeUnavailable = "store-unavailable"
        case unsupported

        static var requested: WatchUITestFixture? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let flagIndex = arguments.firstIndex(of: "-ui-test-watch-fixture"),
                arguments.indices.contains(flagIndex + 1)
            else { return nil }
            return WatchUITestFixture(rawValue: arguments[flagIndex + 1])
        }

        var presentsEndSummary: Bool {
            switch self {
            case .ended, .endedHistoricalTag, .endedLongContent, .endedOffline:
                true
            default:
                false
            }
        }

        @MainActor
        func makeRuntime() throws -> (WellSpentWatchStore, WatchConnectivityState) {
            guard self != .storeUnavailable else { throw WatchStoreError.corruptStore }
            let store = try WellSpentWatchStore.makeEphemeral(
                originDeviceID: Self.originID,
                now: { Self.now }
            )
            guard self != .setup else { return (store, .available(reachable: true, pendingCount: 0)) }

            let snapshot = makeSnapshot()
            _ = try store.installSnapshotData(
                ContractWireCodec.encodeSnapshot(snapshot),
                contradictsPendingMutations: false
            )

            if self != .pending,
                self != .activePending,
                let receiptID = try store.pendingSnapshotReceipts().first?.receiptID
            {
                try store.compactSnapshotReceipt(receiptID: receiptID)
            }

            let connectivityState: WatchConnectivityState =
                switch self {
                case .offline, .activeOffline, .endedOffline:
                    .available(reachable: false, pendingCount: 0)
                case .pending, .activePending: .available(reachable: false, pendingCount: 1)
                case .conflict: .blocked
                default: .available(reachable: true, pendingCount: 0)
                }
            return (store, connectivityState)
        }

        private func makeSnapshot() -> TimerSnapshotEnvelope {
            let catalog: [ProjectSnapshot]
            let tombstones: [EntityTombstone]
            let conflict: TimerConflictSnapshot?
            let updateRequired: Bool

            switch self {
            case .empty, .storeUnavailable:
                catalog = []
                tombstones = []
                conflict = nil
                updateRequired = false
            case .archived:
                catalog = Self.standardProjects + [Self.archivedProject]
                tombstones = [
                    EntityTombstone(
                        entityType: .project,
                        entityID: Self.archivedProject.id,
                        canonicalGeneration: 7,
                        deletedAt: Self.now
                    )
                ]
                conflict = nil
                updateRequired = false
            case .activeArchivedTarget:
                catalog = Self.standardProjects + [Self.archivedProject]
                tombstones = [
                    EntityTombstone(
                        entityType: .project,
                        entityID: Self.archivedProject.id,
                        canonicalGeneration: 7,
                        deletedAt: Self.now
                    )
                ]
                conflict = nil
                updateRequired = false
            case .activeSingleProject:
                catalog = [Self.standardProjects[0]]
                tombstones = []
                conflict = nil
                updateRequired = false
            case .endedHistoricalTag:
                catalog = Self.standardProjects
                tombstones = [
                    EntityTombstone(
                        entityType: .tag,
                        entityID: Self.archivedTagID,
                        canonicalGeneration: 7,
                        deletedAt: Self.now
                    )
                ]
                conflict = nil
                updateRequired = false
            case .endedLongContent:
                catalog = [
                    ProjectSnapshot(
                        id: Self.projectAID,
                        workspaceID: nil,
                        name: "Quarterly launch planning and customer research",
                        colorToken: "purple",
                        symbolName: "🚀"
                    )
                ]
                tombstones = []
                conflict = nil
                updateRequired = false
            case .longNames:
                catalog = [
                    ProjectSnapshot(
                        id: Self.projectAID,
                        workspaceID: nil,
                        name: "Quarterly launch planning and customer research",
                        colorToken: "purple",
                        symbolName: "🚀"
                    ),
                    ProjectSnapshot(
                        id: Self.projectBID,
                        workspaceID: nil,
                        name: "Quarterly launch planning and customer research",
                        colorToken: "orange",
                        symbolName: nil
                    ),
                    ProjectSnapshot(
                        id: Self.projectCID,
                        workspaceID: nil,
                        name: "A",
                        colorToken: nil,
                        symbolName: "folder.fill"
                    ),
                ]
                tombstones = []
                conflict = nil
                updateRequired = false
            case .conflict:
                catalog = Self.standardProjects
                tombstones = []
                conflict = TimerConflictSnapshot(
                    conflictID: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
                    state: .awaitingPhoneReview,
                    reasonCode: .observedStateDiverged,
                    involvedRunIDs: [],
                    involvedSegmentIDs: []
                )
                updateRequired = false
            case .unsupported:
                catalog = Self.standardProjects
                tombstones = []
                conflict = nil
                updateRequired = true
            case .active, .activeNoGoal, .activeOffline, .activePending, .ended,
                .endedOffline, .goalReached, .largeDuration, .offline, .overtime,
                .paused, .pending, .populated, .setup, .staleTotals:
                catalog = Self.standardProjects
                tombstones = []
                conflict = nil
                updateRequired = false
            }

            let fixtureNow = Date()
            let activeFixture = makeActiveFixture(at: fixtureNow)
            let activeRun = activeFixture?.run
            let activeSegments = activeFixture?.segments ?? []
            let endedFixture = makeEndedFixture(at: fixtureNow)
            let endedRun = endedFixture?.run
            let endedSegments = endedFixture?.segments ?? []
            let tagCatalog =
                self == .endedHistoricalTag
                ? Self.standardTags + [Self.archivedTag]
                : Self.standardTags

            return TimerSnapshotEnvelope(
                capabilities: ContractCapability.allCases,
                ledgerHead: TimerLedgerHead(
                    snapshotID: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
                    canonicalGeneration: 7,
                    activeRunID: activeRun?.id,
                    activeRunRevision: activeRun?.revision,
                    headMutationID: nil
                ),
                projects: catalog,
                tags: tagCatalog,
                tombstones: tombstones,
                activeRun: activeRun,
                activeRunSegments: activeSegments,
                recentlyEndedRun: endedRun,
                recentlyEndedRunSegments: endedSegments,
                totals: TimerTotalsSnapshot(
                    todaySeconds: 2_700,
                    weekSeconds: 14_400,
                    calculatedAt: self == .staleTotals
                        ? fixtureNow.addingTimeInterval(-7_200)
                        : fixtureNow,
                    calendarTimeZoneID: TimeZone.current.identifier
                ),
                conflict: conflict,
                recentAcknowledgements: [],
                receiptWatermarks: [],
                updateGuidance: MinimumAppVersionGuidance(
                    minimumPhoneBuild: updateRequired ? 3 : nil,
                    minimumWatchBuild: updateRequired ? 3 : nil,
                    updateRequired: updateRequired
                )
            )
        }

        private func makeActiveFixture(
            at now: Date
        ) -> (run: TimerRunSnapshot, segments: [TimerSegmentSnapshot])? {
            let state: TimerRunState
            let startedAt: Date
            let durationGoalSeconds: Int?
            let segmentIntervals: [(Date, Date?)]

            switch self {
            case .active, .activeArchivedTarget, .activeOffline, .activePending,
                .activeSingleProject, .staleTotals:
                state = .running
                startedAt = now.addingTimeInterval(-125)
                durationGoalSeconds = 1_800
                segmentIntervals = [(startedAt, nil)]
            case .activeNoGoal:
                state = .running
                startedAt = now.addingTimeInterval(-125)
                durationGoalSeconds = nil
                segmentIntervals = [(startedAt, nil)]
            case .paused:
                state = .paused
                startedAt = now.addingTimeInterval(-900)
                durationGoalSeconds = 1_800
                segmentIntervals = [
                    (startedAt, startedAt.addingTimeInterval(420)),
                    (startedAt.addingTimeInterval(540), now.addingTimeInterval(-60)),
                ]
            case .goalReached:
                state = .paused
                startedAt = now.addingTimeInterval(-1_900)
                durationGoalSeconds = 1_800
                segmentIntervals = [(startedAt, startedAt.addingTimeInterval(1_800))]
            case .overtime:
                state = .running
                startedAt = now.addingTimeInterval(-725)
                durationGoalSeconds = 600
                segmentIntervals = [(startedAt, nil)]
            case .largeDuration:
                state = .running
                startedAt = now.addingTimeInterval(-360_005)
                durationGoalSeconds = nil
                segmentIntervals = [(startedAt, nil)]
            default:
                return nil
            }

            let run = TimerRunSnapshot(
                id: Self.runID,
                workspaceID: nil,
                projectID: Self.projectAID,
                state: state,
                startedAt: startedAt,
                endedAt: nil,
                startTimeZoneID: TimeZone.current.identifier,
                endTimeZoneID: nil,
                durationGoalSeconds: durationGoalSeconds,
                normalizedNote: nil,
                tagIDs: [],
                originDeviceID: Self.originID,
                revision: Int64(segmentIntervals.count),
                lastAppliedMutationID: nil,
                createdAt: startedAt,
                updatedAt: segmentIntervals.last?.1 ?? startedAt,
                updatedTimeZoneID: TimeZone.current.identifier
            )
            let segments = segmentIntervals.enumerated().map { index, interval in
                TimerSegmentSnapshot(
                    id: index == 0 ? Self.segmentID : Self.segment2ID,
                    runID: Self.runID,
                    workspaceID: nil,
                    projectID: Self.projectAID,
                    startedAt: interval.0,
                    endedAt: interval.1,
                    startTimeZoneID: TimeZone.current.identifier,
                    endTimeZoneID: interval.1 == nil ? nil : TimeZone.current.identifier,
                    revision: interval.1 == nil ? 1 : 2
                )
            }
            return (run, segments)
        }

        private func makeEndedFixture(
            at now: Date
        ) -> (run: TimerRunSnapshot, segments: [TimerSegmentSnapshot])? {
            guard presentsEndSummary else { return nil }
            let startedAt = now.addingTimeInterval(-900)
            let endedAt = now.addingTimeInterval(-60)
            let note: String?
            let tagIDs: [UUID]
            switch self {
            case .endedHistoricalTag:
                note = "Historical context retained"
                tagIDs = [Self.archivedTagID]
            case .endedLongContent:
                note = String(
                    repeating:
                        "Reviewed research findings, prepared the launch brief, and documented follow-up decisions. ",
                    count: 5
                ).trimmingCharacters(in: .whitespaces)
                tagIDs = Self.standardTags.map(\.id)
            default:
                note = nil
                tagIDs = []
            }
            let run = TimerRunSnapshot(
                id: Self.runID,
                workspaceID: nil,
                projectID: Self.projectAID,
                state: .ended,
                startedAt: startedAt,
                endedAt: endedAt,
                startTimeZoneID: TimeZone.current.identifier,
                endTimeZoneID: TimeZone.current.identifier,
                durationGoalSeconds: 600,
                normalizedNote: note,
                tagIDs: tagIDs,
                originDeviceID: Self.originID,
                revision: 4,
                lastAppliedMutationID: UUID(
                    uuidString: "50000000-0000-0000-0000-000000000004"
                ),
                createdAt: startedAt,
                updatedAt: endedAt,
                updatedTimeZoneID: TimeZone.current.identifier
            )
            let segments = [
                TimerSegmentSnapshot(
                    id: Self.segmentID,
                    runID: Self.runID,
                    workspaceID: nil,
                    projectID: Self.projectAID,
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(420),
                    startTimeZoneID: TimeZone.current.identifier,
                    endTimeZoneID: TimeZone.current.identifier,
                    revision: 2
                ),
                TimerSegmentSnapshot(
                    id: Self.segment2ID,
                    runID: Self.runID,
                    workspaceID: nil,
                    projectID: Self.projectAID,
                    startedAt: startedAt.addingTimeInterval(540),
                    endedAt: endedAt,
                    startTimeZoneID: TimeZone.current.identifier,
                    endTimeZoneID: TimeZone.current.identifier,
                    revision: 2
                ),
            ]
            return (run, segments)
        }

        private static let originID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        private static let projectAID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        private static let projectBID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        private static let projectCID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        private static let runID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        private static let segmentID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        private static let segment2ID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
        private static let archivedTagID = UUID(
            uuidString: "90000000-0000-0000-0000-000000000003"
        )!
        private static let now = Date(timeIntervalSince1970: 1_800_000_000)

        private static let standardProjects = [
            ProjectSnapshot(
                id: projectAID,
                workspaceID: nil,
                name: "Client Launch",
                colorToken: "purple",
                symbolName: "🚀"
            ),
            ProjectSnapshot(
                id: projectBID,
                workspaceID: nil,
                name: "Admin & Operations",
                colorToken: "blue",
                symbolName: "gearshape.fill"
            ),
            ProjectSnapshot(
                id: projectCID,
                workspaceID: nil,
                name: "Deep Work",
                colorToken: "cyan",
                symbolName: "🧠"
            ),
        ]

        private static let standardTags = [
            TagSnapshot(
                id: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
                workspaceID: nil,
                name: "Billable"
            ),
            TagSnapshot(
                id: UUID(uuidString: "90000000-0000-0000-0000-000000000002")!,
                workspaceID: nil,
                name: "Deep focus"
            ),
        ]

        private static let archivedTag = TagSnapshot(
            id: archivedTagID,
            workspaceID: nil,
            name: "Former client phase"
        )

        private static let archivedProject = ProjectSnapshot(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000004")!,
            workspaceID: nil,
            name: "Archived Client",
            colorToken: "red",
            symbolName: "archivebox.fill"
        )
    }
#endif
