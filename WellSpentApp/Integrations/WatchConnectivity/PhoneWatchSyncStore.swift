import Foundation
import SwiftData
import WellSpentWatchContracts

enum PhoneMutationInboxStatus: String {
    case received
    case terminal
}

enum PhoneTimerConflictStatus: String {
    case awaitingPhoneReview = "awaiting_phone_review"
    case resolved
}

enum PhoneConflictResolutionError: Error, Equatable {
    case conflictNotFound(UUID)
    case conflictAlreadyResolved(UUID)
    case invalidResolution
}

struct PhoneConflictBranch: Equatable {
    let mutation: TimerMutationEnvelope
    let projection: TimerConflictBranchProjection?
}

struct PhoneTimerConflict: Equatable {
    let snapshot: TimerConflictSnapshot
    let canonicalSnapshot: TimerSnapshotEnvelope?
    let branches: [PhoneConflictBranch]
    let createdAt: Date
    let resolvedAt: Date?
    let resolutionMutationID: UUID?
}

struct PhoneConflictResolutionResult: Equatable {
    let conflictID: UUID
    let mutationID: UUID
    let resultingHead: TimerLedgerHead
}

struct PhoneAcknowledgementOutboxItem: Equatable {
    let acknowledgementID: UUID
    let mutationID: UUID
    let originDeviceID: UUID
    let canonicalGeneration: UInt64
    let data: Data
    let attemptCount: Int
}

struct PhoneMutationProcessingResult: Equatable {
    let acknowledgements: [MutationAcknowledgement]
    let appliedMutationIDs: [UUID]
    let waitingMutationIDs: [UUID]
}

struct PhoneWatchSyncOverview: Equatable {
    var watchOriginIDs: Set<UUID> = []
    var pendingAcknowledgements = 0
    var awaitingSnapshotReceipt = false
    var hasWatchHistory: Bool { !watchOriginIDs.isEmpty }
}

@MainActor
final class PhoneWatchSyncStore {
    private let context: ModelContext
    private let timerRepository: SwiftDataTimerRunRepository
    private let timerCommands: TimerRunCommandService
    private let dependencies: WellSpentDependencies
    private let showsSystemProjectNames: () -> Bool
    #if DEBUG
        private var afterInboxReceiptSaved: (() throws -> Void)?
        private var beforeSave: (() throws -> Void)?
    #endif

    init(
        context: ModelContext,
        timerRepository: SwiftDataTimerRunRepository,
        timerCommands: TimerRunCommandService,
        dependencies: WellSpentDependencies,
        showsSystemProjectNames: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: AppPreferenceKeys.showProjectNamesOnLockScreen)
        }
    ) {
        self.context = context
        self.timerRepository = timerRepository
        self.timerCommands = timerCommands
        self.dependencies = dependencies
        self.showsSystemProjectNames = showsSystemProjectNames
    }

    #if DEBUG
        func setAfterInboxReceiptSavedForTesting(_ hook: (() throws -> Void)?) {
            afterInboxReceiptSaved = hook
        }

        func setBeforeSaveForTesting(_ hook: (() throws -> Void)?) {
            beforeSave = hook
        }
    #endif

    func receiveMutationData(
        _ data: Data,
        receivedAt: Date? = nil
    ) throws -> PhoneMutationProcessingResult {
        let timestamp = receivedAt ?? dependencies.now
        let header = try ContractWireCodec.decodeMutationHeader(data)
        let resetFloor =
            try context.fetch(FetchDescriptor<PhoneDataResetRecord>())
            .map(\.minimumAcceptedGeneration).max() ?? 0
        if resetFloor > 0,
            let mutation = try? ContractWireCodec.decodeMutation(data),
            mutation.baseCanonicalGeneration < UInt64(resetFloor)
        {
            let head = try synchronizeCanonicalMetadata(saveChanges: true)
            let acknowledgement = MutationAcknowledgement(
                acknowledgementID: dependencies.makeUUID(), mutationID: header.mutationID,
                originDeviceID: header.originDeviceID, originSequence: header.originSequence,
                outcome: .invalid, canonicalSnapshotID: head.snapshotID,
                canonicalGeneration: head.canonicalGeneration, conflictID: nil,
                reasonCode: .staleCausalBase, acknowledgedAt: timestamp
            )
            try ensureAcknowledgementQueued(acknowledgement)
            return PhoneMutationProcessingResult(
                acknowledgements: [acknowledgement], appliedMutationIDs: [], waitingMutationIDs: [])
        }
        let existing = try inboxRecords().filter { $0.mutationID == header.mutationID }
        if let exact = existing.first(where: {
            $0.originDeviceID == header.originDeviceID
                && $0.originSequence == Int64(header.originSequence)
                && $0.payloadDigestHex == header.payloadDigest.hex
        }) {
            if exact.statusRawValue == PhoneMutationInboxStatus.terminal.rawValue,
                let acknowledgementData = exact.acknowledgementData
            {
                let acknowledgement = try ContractWireCodec.decodeCanonical(
                    MutationAcknowledgement.self,
                    from: acknowledgementData
                )
                try ensureAcknowledgementQueued(acknowledgement)
                return PhoneMutationProcessingResult(
                    acknowledgements: [acknowledgement],
                    appliedMutationIDs: [],
                    waitingMutationIDs: []
                )
            }
            return try processReceivedInbox()
        }
        guard header.originSequence > 0, header.originSequence <= UInt64(Int64.max) else {
            throw ContractWireError.invalidEnvelope
        }

        context.insert(
            PhoneMutationInboxRecord(
                mutationID: header.mutationID,
                originDeviceID: header.originDeviceID,
                originSequence: Int64(header.originSequence),
                payloadDigestHex: header.payloadDigest.hex,
                envelopeData: data,
                receivedAt: timestamp
            )
        )
        try save()
        #if DEBUG
            try afterInboxReceiptSaved?()
        #endif
        return try processReceivedInbox()
    }

    func processReceivedInbox() throws -> PhoneMutationProcessingResult {
        _ = try synchronizeCanonicalMetadata(saveChanges: true)
        var acknowledgements: [MutationAcknowledgement] = []
        var appliedIDs: [UUID] = []
        var madeProgress = true

        while madeProgress {
            madeProgress = false
            let received = try inboxRecords()
                .filter { $0.statusRawValue == PhoneMutationInboxStatus.received.rawValue }
                .sorted {
                    if $0.originDeviceID != $1.originDeviceID {
                        return $0.originDeviceID.uuidString < $1.originDeviceID.uuidString
                    }
                    return $0.originSequence < $1.originSequence
                }

            for record in received {
                let result = try process(record)
                switch result {
                case .waiting:
                    continue
                case .terminal(let acknowledgement, let applied):
                    acknowledgements.append(acknowledgement)
                    if applied { appliedIDs.append(record.mutationID) }
                    madeProgress = true
                }
            }
        }

        let waiting = try inboxRecords()
            .filter { $0.statusRawValue == PhoneMutationInboxStatus.received.rawValue }
            .map(\.mutationID)
            .sorted { $0.uuidString < $1.uuidString }
        return PhoneMutationProcessingResult(
            acknowledgements: acknowledgements,
            appliedMutationIDs: appliedIDs,
            waitingMutationIDs: waiting
        )
    }

    func makeSnapshot() throws -> TimerSnapshotEnvelope {
        let head = try synchronizeCanonicalMetadata(saveChanges: true)
        let projects = try activeProjectSnapshots()
        let tags = try activeTagSnapshots()
        let active = try canonicalActiveRun()
        let recent = try recentlyEndedRun(excluding: active?.id)
        try recordDerivedTombstones(
            projects: projects,
            tags: tags,
            activeRunID: active?.id,
            recentlyEndedRunID: recent?.id,
            generation: head.canonicalGeneration,
            at: dependencies.now
        )
        let recentAcknowledgements = try terminalAcknowledgements().suffix(128)
        let calendar = dependencies.makeCalendar()
        let now = dependencies.now
        let totals = TimerTotalsSnapshot(
            todaySeconds: totalSeconds(
                in: DateInterval(
                    start: calendar.startOfDay(for: now),
                    end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
                ),
                now: now
            ),
            weekSeconds: totalSeconds(
                in: calendar.dateInterval(of: .weekOfYear, for: now)
                    ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400),
                now: now
            ),
            calculatedAt: now,
            calendarTimeZoneID: calendar.timeZone.identifier
        )

        let snapshot = TimerSnapshotEnvelope(
            capabilities: ContractCapability.allCases,
            ledgerHead: head,
            projects: projects,
            tags: tags,
            tombstones: try tombstoneSnapshots(),
            activeRun: try active.map(contractRun),
            activeRunSegments: try active.map(contractSegments) ?? [],
            recentlyEndedRun: try recent.map(contractRun),
            recentlyEndedRunSegments: try recent.map(contractSegments) ?? [],
            totals: totals,
            conflict: try activeConflictSnapshot(),
            recentAcknowledgements: Array(recentAcknowledgements),
            receiptWatermarks: try receiptWatermarks(),
            updateGuidance: MinimumAppVersionGuidance(
                minimumPhoneBuild: nil,
                minimumWatchBuild: nil,
                updateRequired: false
            ),
            showProjectNamesOnSystemSurfaces: showsSystemProjectNames()
        )
        try persistCanonicalSnapshot(snapshot)
        return snapshot
    }

    func pendingConflicts() throws -> [PhoneTimerConflict] {
        try conflictRecords()
            .filter { $0.stateRawValue == PhoneTimerConflictStatus.awaitingPhoneReview.rawValue }
            .sorted { $0.createdAt < $1.createdAt }
            .map(visibleConflict)
    }

    func syncOverview() throws -> PhoneWatchSyncOverview {
        let receipts = try snapshotReceiptRecords()
        let origins = Set(try inboxRecords().map(\.originDeviceID) + receipts.map(\.originDeviceID))
        let generation = try synchronizeCanonicalMetadata(saveChanges: true).canonicalGeneration
        return PhoneWatchSyncOverview(
            watchOriginIDs: origins,
            pendingAcknowledgements: try pendingAcknowledgements().count,
            awaitingSnapshotReceipt: !origins.isEmpty
                && (receipts.map(\.canonicalGeneration).max() ?? -1) < Int64(generation)
        )
    }

    func resolveConflict(
        conflictID: UUID,
        resolution: ConflictResolutionPayload,
        capturedAt: Date? = nil,
        timeZoneID: String? = nil,
        mutationID requestedMutationID: UUID? = nil
    ) throws -> PhoneConflictResolutionResult {
        let timestamp = capturedAt ?? dependencies.now
        let zoneID = timeZoneID ?? dependencies.timeZone.identifier
        let mutationID = requestedMutationID ?? dependencies.makeUUID()
        guard timestamp.timeIntervalSinceReferenceDate.isFinite, !zoneID.isEmpty else {
            throw PhoneConflictResolutionError.invalidResolution
        }
        guard let conflict = try conflictRecords().first(where: { $0.conflictID == conflictID })
        else { throw PhoneConflictResolutionError.conflictNotFound(conflictID) }
        if conflict.stateRawValue == PhoneTimerConflictStatus.resolved.rawValue {
            if conflict.resolutionMutationID == mutationID,
                let data = conflict.resolvedHeadData,
                let head = try? ContractWireCodec.decodeCanonical(TimerLedgerHead.self, from: data)
            {
                return PhoneConflictResolutionResult(
                    conflictID: conflictID,
                    mutationID: mutationID,
                    resultingHead: head
                )
            }
            throw PhoneConflictResolutionError.conflictAlreadyResolved(conflictID)
        }

        do {
            try TimerConflictBranchReconstructor.validateResolution(resolution)
            try applyResolution(
                resolution,
                conflict: conflict,
                mutationID: mutationID,
                capturedAt: timestamp,
                timeZoneID: zoneID
            )
            let resultingHead = try advanceCanonicalMetadata(mutationID: mutationID)
            try insertTombstone(
                entityType: .conflictResolution,
                entityID: conflictID,
                generation: resultingHead.canonicalGeneration,
                deletedAt: timestamp,
                conflictID: conflictID
            )
            conflict.stateRawValue = PhoneTimerConflictStatus.resolved.rawValue
            conflict.resolvedAt = timestamp
            conflict.resolutionMutationID = mutationID
            conflict.resolutionPayloadData = try ContractWireCodec.encodeCanonical(resolution)
            conflict.resolvedHeadData = try ContractWireCodec.encodeCanonical(resultingHead)
            try save()
            return PhoneConflictResolutionResult(
                conflictID: conflictID,
                mutationID: mutationID,
                resultingHead: resultingHead
            )
        } catch {
            context.rollback()
            if error is PhoneConflictResolutionError { throw error }
            throw PhoneConflictResolutionError.invalidResolution
        }
    }

    func pendingAcknowledgements() throws -> [PhoneAcknowledgementOutboxItem] {
        try acknowledgementOutboxRecords()
            .sorted { $0.createdAt < $1.createdAt }
            .map { record in
                guard record.canonicalGeneration >= 0,
                    record.attemptCount >= 0,
                    let generation = UInt64(exactly: record.canonicalGeneration),
                    let attempts = Int(exactly: record.attemptCount)
                else { throw ContractWireError.invalidEnvelope }
                return PhoneAcknowledgementOutboxItem(
                    acknowledgementID: record.acknowledgementID,
                    mutationID: record.mutationID,
                    originDeviceID: record.originDeviceID,
                    canonicalGeneration: generation,
                    data: record.acknowledgementData,
                    attemptCount: attempts
                )
            }
    }

    func recordAcknowledgementAttempt(id: UUID, at timestamp: Date) throws {
        guard
            let record = try acknowledgementOutboxRecords().first(where: {
                $0.acknowledgementID == id
            })
        else { return }
        record.attemptCount += 1
        record.lastAttemptAt = timestamp
        try save()
    }

    func receiveSnapshotReceiptData(_ data: Data) throws {
        let receipt = try ContractWireCodec.decodeCanonical(SnapshotReceipt.self, from: data)
        guard receipt.canonicalGeneration <= UInt64(Int64.max) else {
            throw ContractWireError.invalidEnvelope
        }
        if try snapshotReceiptRecords().contains(where: { $0.receiptID == receipt.receiptID }) {
            return
        }
        context.insert(
            PhoneSnapshotReceiptRecord(
                receiptID: receipt.receiptID,
                originDeviceID: receipt.originDeviceID,
                snapshotID: receipt.snapshotID,
                canonicalGeneration: Int64(receipt.canonicalGeneration),
                receiptData: data,
                receivedAt: receipt.receivedAt
            )
        )
        for acknowledgement in try acknowledgementOutboxRecords()
        where acknowledgement.originDeviceID == receipt.originDeviceID
            && acknowledgement.canonicalGeneration <= Int64(receipt.canonicalGeneration)
        {
            context.delete(acknowledgement)
        }
        try compactTombstones(crossedGeneration: Int64(receipt.canonicalGeneration))
        try save()
    }

    private enum RecordProcessingResult {
        case waiting
        case terminal(MutationAcknowledgement, applied: Bool)
    }

    private func process(_ record: PhoneMutationInboxRecord) throws -> RecordProcessingResult {
        let head = try currentHead()
        let mutation: TimerMutationEnvelope
        do {
            mutation = try ContractWireCodec.decodeMutation(record.envelopeData)
        } catch let wireError as ContractWireError {
            let outcome: MutationOutcome =
                wireError == .unsupportedAction || wireError == .unsupportedProtocol
                ? .unsupported : .invalid
            let reason: ContractReasonCode =
                switch wireError {
                case .unsupportedAction: .unsupportedAction
                case .unsupportedProtocol: .unsupportedProtocol
                case .digestMismatch: .digestMismatch
                default: .invalidEnvelope
                }
            let acknowledgement = try finalize(
                record,
                outcome: outcome,
                reason: reason,
                resultingHead: head,
                applied: false
            )
            return .terminal(acknowledgement, applied: false)
        }

        if let conflict = try activeConflictRecord() {
            let conflictHead = try retain(
                mutation,
                record: record,
                in: conflict,
                reason: .predecessorNotApplied,
                currentHead: head
            )
            let acknowledgement = try finalize(
                record,
                outcome: .conflict,
                reason: .predecessorNotApplied,
                resultingHead: conflictHead,
                conflictID: conflict.conflictID,
                applied: false
            )
            return .terminal(acknowledgement, applied: false)
        }

        if case .recoveryProposal = mutation.action {
            let retained = try createConflict(
                for: mutation,
                record: record,
                reason: .invalidEnvelope,
                currentHead: head
            )
            let acknowledgement = try finalize(
                record,
                outcome: .conflict,
                reason: .invalidEnvelope,
                resultingHead: retained.head,
                conflictID: retained.conflictID,
                applied: false
            )
            return .terminal(acknowledgement, applied: false)
        }

        let decision = TimerMutationReconciler.classify(
            mutation,
            in: try reconciliationContext(head: head)
        )
        switch decision {
        case .awaitPredecessor:
            return .waiting
        case .duplicate:
            let acknowledgement = try finalize(
                record,
                outcome: .duplicate,
                reason: .duplicate,
                resultingHead: head,
                applied: false
            )
            return .terminal(acknowledgement, applied: false)
        case .reject(let reason):
            let outcome: MutationOutcome =
                reason == .unsupportedAction || reason == .unsupportedProtocol
                ? .unsupported : .invalid
            let acknowledgement = try finalize(
                record,
                outcome: outcome,
                reason: reason,
                resultingHead: head,
                applied: false
            )
            return .terminal(acknowledgement, applied: false)
        case .reviewRequired(let reason):
            let retained = try createConflict(
                for: mutation,
                record: record,
                reason: reason,
                currentHead: head
            )
            let acknowledgement = try finalize(
                record,
                outcome: .conflict,
                reason: reason,
                resultingHead: retained.head,
                conflictID: retained.conflictID,
                applied: false
            )
            return .terminal(acknowledgement, applied: false)
        case .apply:
            break
        }

        do {
            try apply(mutation)
            let resultingHead = try advanceCanonicalMetadata(mutationID: mutation.mutationID)
            let acknowledgement = try finalize(
                record,
                outcome: .applied,
                reason: .applied,
                resultingHead: resultingHead,
                applied: true
            )
            return .terminal(acknowledgement, applied: true)
        } catch let commandError as TimerRunCommandError {
            context.rollback()
            guard
                let refreshed = try inboxRecords().first(where: {
                    $0.mutationID == record.mutationID
                        && $0.payloadDigestHex == record.payloadDigestHex
                })
            else { throw commandError }
            let current = try currentHead()
            if commandRequiresReview(commandError) {
                let retained = try createConflict(
                    for: mutation,
                    record: refreshed,
                    reason: reasonCode(for: commandError),
                    currentHead: current
                )
                let acknowledgement = try finalize(
                    refreshed,
                    outcome: .conflict,
                    reason: reasonCode(for: commandError),
                    resultingHead: retained.head,
                    conflictID: retained.conflictID,
                    applied: false
                )
                return .terminal(acknowledgement, applied: false)
            }
            let acknowledgement = try finalize(
                refreshed,
                outcome: .invalid,
                reason: .invalidEnvelope,
                resultingHead: current,
                applied: false
            )
            return .terminal(acknowledgement, applied: false)
        }
    }

    private func apply(_ mutation: TimerMutationEnvelope) throws {
        switch mutation.action {
        case .start(let action):
            guard mutation.observedRunID == nil else {
                throw TimerRunCommandError.runIsNotCurrent(action.runID)
            }
            _ = try timerCommands.start(
                projectID: action.projectID,
                durationGoalSeconds: action.durationGoalSeconds.map(Double.init),
                mutationID: mutation.mutationID,
                capturedAt: mutation.capturedAt,
                timeZoneID: mutation.capturedTimeZoneID,
                runID: action.runID,
                segmentID: action.segmentID,
                originDeviceID: mutation.originDeviceID,
                saveChanges: false
            )
        case .pause(let action):
            _ = try timerCommands.pause(
                runID: action.runID,
                capturedAt: mutation.capturedAt,
                timeZoneID: mutation.capturedTimeZoneID,
                mutationID: mutation.mutationID,
                expectedOpenSegmentID: action.openSegmentID,
                saveChanges: false
            )
        case .resume(let action):
            _ = try timerCommands.resume(
                runID: action.runID,
                capturedAt: mutation.capturedAt,
                timeZoneID: mutation.capturedTimeZoneID,
                mutationID: mutation.mutationID,
                newSegmentID: action.newSegmentID,
                saveChanges: false
            )
        case .switch(let action):
            _ = try timerCommands.switchTimer(
                to: action.projectID,
                durationGoalSeconds: action.durationGoalSeconds.map(Double.init),
                capturedAt: mutation.capturedAt,
                timeZoneID: mutation.capturedTimeZoneID,
                mutationID: mutation.mutationID,
                expectedOpenSegmentID: action.openSegmentID,
                toRunID: action.toRunID,
                toSegmentID: action.toSegmentID,
                originDeviceID: mutation.originDeviceID,
                saveChanges: false
            )
        case .end(let action):
            _ = try timerCommands.end(
                runID: action.runID,
                capturedAt: mutation.capturedAt,
                timeZoneID: mutation.capturedTimeZoneID,
                mutationID: mutation.mutationID,
                expectedOpenSegmentID: action.openSegmentID,
                saveChanges: false
            )
        case .annotate(let action):
            _ = try timerCommands.annotate(
                runID: action.runID,
                note: action.normalizedNote,
                tagIDs: Set(action.tagIDs),
                mutationID: mutation.mutationID,
                capturedAt: mutation.capturedAt,
                timeZoneID: mutation.capturedTimeZoneID,
                saveChanges: false
            )
        case .setGoal(let action):
            _ = try timerCommands.setGoal(
                runID: action.runID,
                durationGoalSeconds: action.durationGoalSeconds.map(Double.init),
                mutationID: mutation.mutationID,
                capturedAt: mutation.capturedAt,
                timeZoneID: mutation.capturedTimeZoneID,
                saveChanges: false
            )
        case .recoveryProposal, .resolveConflict:
            throw TimerRunCommandError.invalidRevision
        }
    }

    private func commandRequiresReview(_ error: TimerRunCommandError) -> Bool {
        switch error {
        case .invalidGoal, .invalidTags, .invalidTimestamp, .projectNotFound:
            false
        case .deletionRequiresConfirmation, .endedRunRequired, .identityCollision,
            .invalidRevision, .noActiveRun, .nonIncreasingBoundary, .projectArchived,
            .reviewRequired, .runIsNotCurrent, .runNotFound, .runRequiresSwitch:
            true
        }
    }

    private func reasonCode(for error: TimerRunCommandError) -> ContractReasonCode {
        switch error {
        case .identityCollision:
            .mutationIdentityCollision
        case .runIsNotCurrent, .runNotFound, .runRequiresSwitch, .noActiveRun:
            .observedStateDiverged
        case .projectArchived:
            .staleCausalBase
        case .reviewRequired, .nonIncreasingBoundary, .invalidRevision, .endedRunRequired,
            .deletionRequiresConfirmation:
            .invalidEnvelope
        case .invalidGoal, .invalidTags, .invalidTimestamp, .projectNotFound:
            .invalidEnvelope
        }
    }

    private func createConflict(
        for mutation: TimerMutationEnvelope,
        record: PhoneMutationInboxRecord,
        reason: ContractReasonCode,
        currentHead: TimerLedgerHead
    ) throws -> (conflictID: UUID, head: TimerLedgerHead) {
        let conflictID = dependencies.makeUUID()
        let identities = try conflictIdentities(for: mutation, currentHead: currentHead)
        let canonicalData = try canonicalSnapshotRecords().first(where: {
            $0.snapshotID == currentHead.snapshotID
                && $0.canonicalGeneration == Int64(currentHead.canonicalGeneration)
        })?.snapshotData
        let conflict = PhoneTimerConflictRecord(
            conflictID: conflictID,
            stateRawValue: PhoneTimerConflictStatus.awaitingPhoneReview.rawValue,
            reasonCodeRawValue: reason.rawValue,
            canonicalHeadData: try ContractWireCodec.encodeCanonical(currentHead),
            canonicalSnapshotData: canonicalData,
            involvedRunIDsData: try ContractWireCodec.encodeCanonical(identities.runs),
            involvedSegmentIDsData: try ContractWireCodec.encodeCanonical(identities.segments),
            createdAt: record.receivedAt
        )
        context.insert(conflict)
        try insertConflictMutation(mutation, record: record, conflict: conflict)
        let resultingHead = try advanceCanonicalMetadata(mutationID: mutation.mutationID)
        return (conflictID, resultingHead)
    }

    private func retain(
        _ mutation: TimerMutationEnvelope,
        record: PhoneMutationInboxRecord,
        in conflict: PhoneTimerConflictRecord,
        reason: ContractReasonCode,
        currentHead: TimerLedgerHead
    ) throws -> TimerLedgerHead {
        if !(try conflictMutationRecords()).contains(where: {
            $0.conflictID == conflict.conflictID && $0.mutationID == mutation.mutationID
        }) {
            try insertConflictMutation(mutation, record: record, conflict: conflict)
        }
        let existingRuns = try decodeUUIDs(conflict.involvedRunIDsData)
        let existingSegments = try decodeUUIDs(conflict.involvedSegmentIDsData)
        let newIdentities = try conflictIdentities(for: mutation, currentHead: currentHead)
        conflict.involvedRunIDsData = try ContractWireCodec.encodeCanonical(
            stableUUIDs(existingRuns + newIdentities.runs)
        )
        conflict.involvedSegmentIDsData = try ContractWireCodec.encodeCanonical(
            stableUUIDs(existingSegments + newIdentities.segments)
        )
        if conflict.reasonCodeRawValue.isEmpty {
            conflict.reasonCodeRawValue = reason.rawValue
        }
        return try advanceCanonicalMetadata(mutationID: mutation.mutationID)
    }

    private func insertConflictMutation(
        _ mutation: TimerMutationEnvelope,
        record: PhoneMutationInboxRecord,
        conflict: PhoneTimerConflictRecord
    ) throws {
        guard mutation.originSequence <= UInt64(Int64.max) else {
            throw ContractWireError.invalidEnvelope
        }
        let branchData = try reconstructedBranchData(
            adding: mutation,
            conflictID: conflict.conflictID
        )
        context.insert(
            PhoneConflictMutationRecord(
                recordID: dependencies.makeUUID(),
                conflictID: conflict.conflictID,
                mutationID: mutation.mutationID,
                originDeviceID: mutation.originDeviceID,
                originSequence: Int64(mutation.originSequence),
                envelopeData: record.envelopeData,
                reconstructedBranchData: branchData,
                receivedAt: record.receivedAt
            )
        )
    }

    private func reconstructedBranchData(
        adding mutation: TimerMutationEnvelope,
        conflictID: UUID
    ) throws -> Data? {
        guard let baseID = mutation.baseSnapshotID,
            let baseRecord = try canonicalSnapshotRecords().first(where: {
                $0.snapshotID == baseID
                    && $0.canonicalGeneration == Int64(mutation.baseCanonicalGeneration)
            }),
            let base = try? ContractWireCodec.decodeSnapshot(baseRecord.snapshotData)
        else { return nil }

        var chain = try conflictMutationRecords()
            .filter {
                $0.conflictID == conflictID
                    && $0.originDeviceID == mutation.originDeviceID
                    && $0.originSequence < Int64(mutation.originSequence)
            }
            .compactMap { try? ContractWireCodec.decodeMutation($0.envelopeData) }
        chain.append(mutation)
        guard
            let projection = try? TimerConflictBranchReconstructor.reconstruct(
                base: base,
                mutations: chain
            )
        else { return nil }
        return try ContractWireCodec.encodeCanonical(projection)
    }

    private func conflictIdentities(
        for mutation: TimerMutationEnvelope,
        currentHead: TimerLedgerHead
    ) throws -> (runs: [UUID], segments: [UUID]) {
        var runs = currentHead.activeRunID.map { [$0] } ?? []
        var segments: [UUID] = []
        if let active = try canonicalActiveRun() {
            segments.append(contentsOf: try timerRepository.fetchSegments(runID: active.id).map(\.id))
        }
        switch mutation.action {
        case .start(let action):
            runs.append(action.runID)
            segments.append(action.segmentID)
        case .pause(let action):
            runs.append(action.runID)
            segments.append(action.openSegmentID)
        case .resume(let action):
            runs.append(action.runID)
            segments.append(action.newSegmentID)
        case .switch(let action):
            runs.append(contentsOf: [action.fromRunID, action.toRunID])
            if let open = action.openSegmentID { segments.append(open) }
            segments.append(action.toSegmentID)
        case .end(let action):
            runs.append(action.runID)
            if let open = action.openSegmentID { segments.append(open) }
        case .annotate(let action):
            runs.append(action.runID)
        case .setGoal(let action):
            runs.append(action.runID)
        case .recoveryProposal(let action):
            runs.append(action.run.id)
            segments.append(contentsOf: action.segments.map(\.id))
        case .resolveConflict(let action):
            runs.append(contentsOf: action.resolution.retainedRunIDs)
            runs.append(contentsOf: action.resolution.replacementRuns.map(\.id))
            segments.append(contentsOf: action.resolution.replacementSegments.map(\.id))
        }
        return (stableUUIDs(runs), stableUUIDs(segments))
    }

    private func applyResolution(
        _ resolution: ConflictResolutionPayload,
        conflict: PhoneTimerConflictRecord,
        mutationID: UUID,
        capturedAt: Date,
        timeZoneID: String
    ) throws {
        let involvedIDs = Set(try decodeUUIDs(conflict.involvedRunIDsData))
        let retainedIDs = Set(resolution.retainedRunIDs)
        let visibleRuns = try timerRepository.fetchRuns()
        let visibleByID = Dictionary(uniqueKeysWithValues: visibleRuns.map { ($0.id, $0) })
        guard retainedIDs.isSubset(of: involvedIDs),
            retainedIDs.allSatisfy({ visibleByID[$0] != nil })
        else { throw PhoneConflictResolutionError.invalidResolution }

        let replacementIDs = Set(resolution.replacementRuns.map(\.id))
        guard
            replacementIDs.isDisjoint(
                with: Set(
                    try timerRepository.fetchAllRunsIncludingSuperseded().map(\.id)
                ))
        else { throw PhoneConflictResolutionError.invalidResolution }
        let existingSessionIDs = Set(
            try timerRepository.fetchAllSessionsIncludingSuperseded().map(\.id)
        )
        guard
            existingSessionIDs.isDisjoint(
                with: Set(resolution.replacementSegments.map(\.id))
            )
        else { throw PhoneConflictResolutionError.invalidResolution }

        let unaffected = visibleRuns.filter { !involvedIDs.contains($0.id) }
        let retained = retainedIDs.compactMap { visibleByID[$0] }
        let nonEndedIDs =
            unaffected.filter { $0.state != .ended }.map(\.id)
            + retained.filter { $0.state != .ended }.map(\.id)
            + resolution.replacementRuns.filter { $0.state != .ended }.map(\.id)
        guard nonEndedIDs.count <= 1,
            resolution.chosenActiveRunID == nonEndedIDs.first
        else { throw PhoneConflictResolutionError.invalidResolution }

        let current = try currentHead()
        guard current.canonicalGeneration < UInt64(Int64.max) else {
            throw PhoneConflictResolutionError.invalidResolution
        }
        let resolutionGeneration = current.canonicalGeneration + 1
        for run in visibleRuns where involvedIDs.contains(run.id) && !retainedIDs.contains(run.id) {
            try insertTombstone(
                entityType: .run,
                entityID: run.id,
                generation: resolutionGeneration,
                deletedAt: capturedAt,
                conflictID: conflict.conflictID
            )
        }

        let tagsByID = Dictionary(
            uniqueKeysWithValues: try timerRepository.fetchTags().map {
                ($0.id, $0)
            })
        for replacement in resolution.replacementRuns {
            let tagIDs = Set(replacement.tagIDs)
            guard tagIDs.allSatisfy({ tagsByID[$0] != nil }) else {
                throw PhoneConflictResolutionError.invalidResolution
            }
            let state: TimerRunState =
                switch replacement.state {
                case .running: .running
                case .paused: .paused
                case .ended: .ended
                }
            let run = TimerRunRecord(
                id: replacement.id,
                workspaceID: replacement.workspaceID,
                projectID: replacement.projectID,
                state: state,
                startAt: replacement.startedAt,
                endAt: replacement.endedAt,
                startTimeZoneID: replacement.startTimeZoneID,
                endTimeZoneID: replacement.endTimeZoneID,
                durationGoalSeconds: replacement.durationGoalSeconds.map(Double.init),
                note: replacement.normalizedNote,
                originDeviceID: replacement.originDeviceID,
                revision: replacement.revision,
                lastAppliedMutationID: mutationID,
                createdAt: replacement.createdAt,
                updatedAt: capturedAt,
                updatedTimeZoneID: timeZoneID
            )
            timerRepository.insert(run)
            for segment in resolution.replacementSegments.filter({ $0.runID == run.id }) {
                timerRepository.insert(
                    TimeSessionRecord(
                        id: segment.id,
                        workspaceID: segment.workspaceID,
                        projectID: segment.projectID,
                        source: .timer,
                        timerRunID: run.id,
                        startAt: segment.startedAt,
                        endAt: segment.endedAt,
                        startTimeZoneID: segment.startTimeZoneID,
                        endTimeZoneID: segment.endTimeZoneID,
                        note: replacement.normalizedNote,
                        createdAt: replacement.createdAt,
                        updatedAt: capturedAt
                    )
                )
                for tagID in replacement.tagIDs {
                    guard let tag = tagsByID[tagID] else { continue }
                    timerRepository.insert(
                        SessionTagAssignmentRecord(
                            id: dependencies.makeUUID(),
                            workspaceID: segment.workspaceID,
                            sessionID: segment.id,
                            tagID: tagID,
                            nameSnapshot: tag.name,
                            createdAt: capturedAt
                        )
                    )
                }
            }
            for tagID in replacement.tagIDs {
                guard let tag = tagsByID[tagID] else { continue }
                timerRepository.insert(
                    TimerRunTagAssignmentRecord(
                        id: dependencies.makeUUID(),
                        workspaceID: replacement.workspaceID,
                        timerRunID: replacement.id,
                        tagID: tagID,
                        nameSnapshot: tag.name,
                        createdAt: capturedAt
                    )
                )
            }
        }
    }

    private func finalize(
        _ record: PhoneMutationInboxRecord,
        outcome: MutationOutcome,
        reason: ContractReasonCode,
        resultingHead: TimerLedgerHead,
        conflictID: UUID? = nil,
        applied: Bool
    ) throws -> MutationAcknowledgement {
        let timestamp = dependencies.now
        let acknowledgement = MutationAcknowledgement(
            acknowledgementID: dependencies.makeUUID(),
            mutationID: record.mutationID,
            originDeviceID: record.originDeviceID,
            originSequence: UInt64(record.originSequence),
            outcome: outcome,
            canonicalSnapshotID: resultingHead.snapshotID,
            canonicalGeneration: resultingHead.canonicalGeneration,
            conflictID: conflictID,
            reasonCode: reason,
            acknowledgedAt: timestamp
        )
        let acknowledgementData = try ContractWireCodec.encodeCanonical(acknowledgement)
        record.statusRawValue = PhoneMutationInboxStatus.terminal.rawValue
        record.outcomeRawValue = outcome.rawValue
        record.reasonCodeRawValue = reason.rawValue
        record.acknowledgementData = acknowledgementData
        record.resultingHeadData = try ContractWireCodec.encodeCanonical(resultingHead)
        record.completedAt = timestamp
        context.insert(
            PhoneAcknowledgementOutboxRecord(
                acknowledgementID: acknowledgement.acknowledgementID,
                mutationID: acknowledgement.mutationID,
                originDeviceID: acknowledgement.originDeviceID,
                canonicalGeneration: Int64(acknowledgement.canonicalGeneration),
                acknowledgementData: acknowledgementData,
                createdAt: timestamp
            )
        )
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
        return acknowledgement
    }

    private func ensureAcknowledgementQueued(_ acknowledgement: MutationAcknowledgement) throws {
        guard
            !((try acknowledgementOutboxRecords()).contains {
                $0.acknowledgementID == acknowledgement.acknowledgementID
            })
        else { return }
        context.insert(
            PhoneAcknowledgementOutboxRecord(
                acknowledgementID: acknowledgement.acknowledgementID,
                mutationID: acknowledgement.mutationID,
                originDeviceID: acknowledgement.originDeviceID,
                canonicalGeneration: Int64(acknowledgement.canonicalGeneration),
                acknowledgementData: try ContractWireCodec.encodeCanonical(acknowledgement),
                createdAt: acknowledgement.acknowledgedAt
            )
        )
        try save()
    }

    private func synchronizeCanonicalMetadata(saveChanges: Bool) throws -> TimerLedgerHead {
        let metadata = try requiredMetadata()
        let signature = try canonicalSignature()
        if metadata.stateSignatureHex == nil {
            metadata.stateSignatureHex = signature
            if try hasCanonicalContent() {
                metadata.canonicalGeneration = 1
                metadata.snapshotID = dependencies.makeUUID()
            }
            metadata.headMutationID = try mostRecentMutationID()
            metadata.updatedAt = dependencies.now
            if saveChanges { try save() }
        } else if metadata.stateSignatureHex != signature {
            guard metadata.canonicalGeneration >= 0, metadata.canonicalGeneration < Int64.max else {
                throw ContractWireError.invalidEnvelope
            }
            metadata.canonicalGeneration += 1
            metadata.snapshotID = dependencies.makeUUID()
            metadata.stateSignatureHex = signature
            metadata.headMutationID = try mostRecentMutationID()
            metadata.updatedAt = dependencies.now
            if saveChanges { try save() }
        }
        return try head(metadata)
    }

    private func advanceCanonicalMetadata(mutationID: UUID) throws -> TimerLedgerHead {
        let metadata = try requiredMetadata()
        guard metadata.canonicalGeneration >= 0, metadata.canonicalGeneration < Int64.max else {
            throw ContractWireError.invalidEnvelope
        }
        metadata.canonicalGeneration += 1
        metadata.snapshotID = dependencies.makeUUID()
        metadata.stateSignatureHex = try canonicalSignature()
        metadata.headMutationID = mutationID
        metadata.updatedAt = dependencies.now
        return try head(metadata)
    }

    private func currentHead() throws -> TimerLedgerHead {
        try head(requiredMetadata())
    }

    private func head(_ metadata: PhoneSyncMetadataRecord) throws -> TimerLedgerHead {
        guard metadata.canonicalGeneration >= 0,
            let generation = UInt64(exactly: metadata.canonicalGeneration)
        else { throw ContractWireError.invalidEnvelope }
        let active = try canonicalActiveRun()
        return TimerLedgerHead(
            snapshotID: metadata.snapshotID,
            canonicalGeneration: generation,
            activeRunID: active?.id,
            activeRunRevision: active?.revision,
            headMutationID: metadata.headMutationID
        )
    }

    private func reconciliationContext(head: TimerLedgerHead) throws
        -> MutationReconciliationContext
    {
        var byID: [UUID: AppliedMutationRecord] = [:]
        var bySequence: [OriginSequenceKey: AppliedMutationRecord] = [:]
        for record in try inboxRecords()
        where record.statusRawValue == PhoneMutationInboxStatus.terminal.rawValue {
            guard let rawOutcome = record.outcomeRawValue,
                let outcome = MutationOutcome(rawValue: rawOutcome),
                let resultingHeadData = record.resultingHeadData,
                let digest = try? SHA256Digest(hex: record.payloadDigestHex),
                let sequence = UInt64(exactly: record.originSequence),
                let envelope = try? ContractWireCodec.decodeMutation(record.envelopeData),
                let resultingHead = try? ContractWireCodec.decodeCanonical(
                    TimerLedgerHead.self,
                    from: resultingHeadData
                )
            else { continue }
            let applied = AppliedMutationRecord(
                mutationID: record.mutationID,
                originDeviceID: record.originDeviceID,
                originSequence: sequence,
                payloadDigest: digest,
                outcome: outcome,
                resultingHead: resultingHead,
                baseSnapshotID: envelope.baseSnapshotID,
                baseCanonicalGeneration: envelope.baseCanonicalGeneration,
                predecessorMutationID: envelope.predecessorMutationID
            )
            byID[record.mutationID] = applied
            bySequence[
                OriginSequenceKey(
                    originDeviceID: record.originDeviceID,
                    originSequence: sequence
                )
            ] = applied
        }
        return MutationReconciliationContext(
            canonicalHead: head,
            mutationsByID: byID,
            mutationsByOriginSequence: bySequence
        )
    }

    private func requiredMetadata() throws -> PhoneSyncMetadataRecord {
        let records = try context.fetch(FetchDescriptor<PhoneSyncMetadataRecord>())
        guard records.count <= 1 else { throw ContractWireError.invalidEnvelope }
        if let record = records.first { return record }
        let record = PhoneSyncMetadataRecord(
            snapshotID: dependencies.makeUUID(),
            updatedAt: dependencies.now
        )
        let floor =
            try context.fetch(FetchDescriptor<PhoneDataResetRecord>())
            .map(\.minimumAcceptedGeneration).max() ?? 0
        if floor > 0 {
            record.canonicalGeneration = floor
            record.stateSignatureHex = ""
        }
        context.insert(record)
        try save()
        return record
    }

    private func canonicalActiveRun() throws -> TimerRunRecord? {
        let active = try timerRepository.fetchRuns().filter {
            $0.state == .running || $0.state == .paused
        }
        return active.count == 1 ? active[0] : nil
    }

    private func recentlyEndedRun(excluding runID: UUID?) throws -> TimerRunRecord? {
        try timerRepository.fetchRuns()
            .filter { $0.state == .ended && $0.id != runID }
            .max {
                ($0.endAt ?? $0.updatedAt, $0.id.uuidString)
                    < ($1.endAt ?? $1.updatedAt, $1.id.uuidString)
            }
    }

    private func activeProjectSnapshots() throws -> [WellSpentWatchContracts.ProjectSnapshot] {
        let projects = try context.fetch(FetchDescriptor<ProjectRecord>())
            .filter { $0.status == .active }
            .prefix(250)
            .map {
                WellSpentWatchContracts.ProjectSnapshot(
                    id: $0.id,
                    workspaceID: $0.workspaceID,
                    name: $0.name,
                    colorToken: $0.colorToken,
                    symbolName: $0.emoji
                )
            }
        return ContractStableOrdering.projects(Array(projects))
    }

    private func activeTagSnapshots() throws -> [TagSnapshot] {
        let tags = try timerRepository.fetchTags()
            .filter { $0.status == .active }
            .prefix(250)
            .map { TagSnapshot(id: $0.id, workspaceID: $0.workspaceID, name: $0.name) }
        return ContractStableOrdering.tags(Array(tags))
    }

    private func contractRun(_ run: TimerRunRecord) throws
        -> WellSpentWatchContracts.TimerRunSnapshot
    {
        guard let state = run.state else { throw ContractWireError.invalidEnvelope }
        let contractState: WellSpentWatchContracts.TimerRunState =
            switch state {
            case .running: .running
            case .paused: .paused
            case .ended: .ended
            }
        let tagIDs = try timerRepository.fetchRunTagAssignments(runID: run.id)
            .map(\.tagID)
            .sorted { $0.uuidString < $1.uuidString }
        return WellSpentWatchContracts.TimerRunSnapshot(
            id: run.id,
            workspaceID: run.workspaceID,
            projectID: run.projectID,
            state: contractState,
            startedAt: run.startAt,
            endedAt: run.endAt,
            startTimeZoneID: run.startTimeZoneID,
            endTimeZoneID: run.endTimeZoneID,
            durationGoalSeconds: run.durationGoalSeconds.map { Int($0.rounded()) },
            normalizedNote: run.note,
            tagIDs: tagIDs,
            originDeviceID: run.originDeviceID,
            revision: run.revision,
            lastAppliedMutationID: run.lastAppliedMutationID,
            createdAt: run.createdAt,
            updatedAt: run.updatedAt,
            updatedTimeZoneID: run.updatedTimeZoneID
        )
    }

    private func contractSegments(_ run: TimerRunRecord) throws -> [TimerSegmentSnapshot] {
        ContractStableOrdering.segments(
            try timerRepository.fetchSegments(runID: run.id).map {
                TimerSegmentSnapshot(
                    id: $0.id,
                    runID: run.id,
                    workspaceID: $0.workspaceID,
                    projectID: $0.projectID,
                    startedAt: $0.startAt,
                    endedAt: $0.endAt,
                    startTimeZoneID: $0.startTimeZoneID,
                    endTimeZoneID: $0.endTimeZoneID,
                    revision: run.revision
                )
            }
        )
    }

    private struct CanonicalSignature: Codable {
        let projects: [WellSpentWatchContracts.ProjectSnapshot]
        let tags: [TagSnapshot]
        let runs: [WellSpentWatchContracts.TimerRunSnapshot]
        let segments: [TimerSegmentSnapshot]
        let showProjectNamesOnSystemSurfaces: Bool
    }

    private func canonicalSignature() throws -> String {
        let runs = try timerRepository.fetchRuns().filter { $0.state != nil }
        let signature = CanonicalSignature(
            projects: try activeProjectSnapshots(),
            tags: try activeTagSnapshots(),
            runs: try runs.map(contractRun),
            segments: try runs.flatMap(contractSegments),
            showProjectNamesOnSystemSurfaces: showsSystemProjectNames()
        )
        return SHA256Digest.hashing(
            try ContractWireCodec.encodeCanonical(signature)
        ).hex
    }

    private func hasCanonicalContent() throws -> Bool {
        let projects = try context.fetch(FetchDescriptor<ProjectRecord>())
        let runs = try timerRepository.fetchRuns()
        let tags = try timerRepository.fetchTags()
        return !projects.isEmpty || !runs.isEmpty || !tags.isEmpty
    }

    private func mostRecentMutationID() throws -> UUID? {
        try timerRepository.fetchRuns()
            .filter { $0.lastAppliedMutationID != nil }
            .max { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }?
            .lastAppliedMutationID
    }

    private func totalSeconds(in interval: DateInterval, now: Date) -> Int {
        let total =
            (try? timerRepository.fetchSessions())?.reduce(0.0) { partial, session in
                let end = session.endAt ?? now
                let start = max(session.startAt, interval.start)
                let boundedEnd = min(end, interval.end)
                return partial + max(0, boundedEnd.timeIntervalSince(start))
            } ?? 0
        return Int(total.rounded(.down))
    }

    private func terminalAcknowledgements() throws -> [MutationAcknowledgement] {
        try inboxRecords()
            .filter { $0.statusRawValue == PhoneMutationInboxStatus.terminal.rawValue }
            .compactMap { record in
                guard let data = record.acknowledgementData else { return nil }
                return try? ContractWireCodec.decodeCanonical(
                    MutationAcknowledgement.self,
                    from: data
                )
            }
            .sorted { $0.acknowledgedAt < $1.acknowledgedAt }
    }

    private func receiptWatermarks() throws -> [OriginReceiptWatermark] {
        let terminal = try inboxRecords().filter {
            $0.statusRawValue == PhoneMutationInboxStatus.terminal.rawValue
        }
        return Dictionary(grouping: terminal, by: \.originDeviceID)
            .map { origin, records in
                let sequences = Set(records.compactMap { UInt64(exactly: $0.originSequence) })
                var contiguous: UInt64 = 0
                while sequences.contains(contiguous + 1) { contiguous += 1 }
                return OriginReceiptWatermark(
                    originDeviceID: origin,
                    contiguousSequence: contiguous
                )
            }
            .sorted { $0.originDeviceID.uuidString < $1.originDeviceID.uuidString }
    }

    private func activeConflictRecord() throws -> PhoneTimerConflictRecord? {
        try conflictRecords()
            .filter { $0.stateRawValue == PhoneTimerConflictStatus.awaitingPhoneReview.rawValue }
            .min { $0.createdAt < $1.createdAt }
    }

    private func activeConflictSnapshot() throws -> TimerConflictSnapshot? {
        guard let record = try activeConflictRecord(),
            let reason = ContractReasonCode(rawValue: record.reasonCodeRawValue)
        else { return nil }
        return TimerConflictSnapshot(
            conflictID: record.conflictID,
            state: .awaitingPhoneReview,
            reasonCode: reason,
            involvedRunIDs: try decodeUUIDs(record.involvedRunIDsData),
            involvedSegmentIDs: try decodeUUIDs(record.involvedSegmentIDsData)
        )
    }

    private func visibleConflict(_ record: PhoneTimerConflictRecord) throws
        -> PhoneTimerConflict
    {
        guard let reason = ContractReasonCode(rawValue: record.reasonCodeRawValue) else {
            throw ContractWireError.invalidEnvelope
        }
        let state: TimerConflictState =
            record.stateRawValue == PhoneTimerConflictStatus.resolved.rawValue
            ? .resolved : .awaitingPhoneReview
        let canonical = try record.canonicalSnapshotData.map {
            try ContractWireCodec.decodeSnapshot($0)
        }
        let branches = try conflictMutationRecords()
            .filter { $0.conflictID == record.conflictID }
            .sorted {
                if $0.originDeviceID != $1.originDeviceID {
                    return $0.originDeviceID.uuidString < $1.originDeviceID.uuidString
                }
                return $0.originSequence < $1.originSequence
            }
            .map { mutationRecord in
                PhoneConflictBranch(
                    mutation: try ContractWireCodec.decodeMutation(
                        mutationRecord.envelopeData
                    ),
                    projection: try mutationRecord.reconstructedBranchData.map {
                        try ContractWireCodec.decodeCanonical(
                            TimerConflictBranchProjection.self,
                            from: $0
                        )
                    }
                )
            }
        return PhoneTimerConflict(
            snapshot: TimerConflictSnapshot(
                conflictID: record.conflictID,
                state: state,
                reasonCode: reason,
                involvedRunIDs: try decodeUUIDs(record.involvedRunIDsData),
                involvedSegmentIDs: try decodeUUIDs(record.involvedSegmentIDsData)
            ),
            canonicalSnapshot: canonical,
            branches: branches,
            createdAt: record.createdAt,
            resolvedAt: record.resolvedAt,
            resolutionMutationID: record.resolutionMutationID
        )
    }

    private func recordDerivedTombstones(
        projects: [WellSpentWatchContracts.ProjectSnapshot],
        tags: [TagSnapshot],
        activeRunID: UUID?,
        recentlyEndedRunID: UUID?,
        generation: UInt64,
        at timestamp: Date
    ) throws {
        guard
            let previousRecord = try canonicalSnapshotRecords().max(by: {
                $0.canonicalGeneration < $1.canonicalGeneration
            }),
            let previous = try? ContractWireCodec.decodeSnapshot(previousRecord.snapshotData)
        else { return }
        let projectIDs = Set(projects.map(\.id))
        for removedID in Set(previous.projects.map(\.id)).subtracting(projectIDs) {
            try insertTombstone(
                entityType: .project,
                entityID: removedID,
                generation: generation,
                deletedAt: timestamp,
                conflictID: nil
            )
        }
        let tagIDs = Set(tags.map(\.id))
        for removedID in Set(previous.tags.map(\.id)).subtracting(tagIDs) {
            try insertTombstone(
                entityType: .tag,
                entityID: removedID,
                generation: generation,
                deletedAt: timestamp,
                conflictID: nil
            )
        }
        let currentRunIDs = Set([activeRunID, recentlyEndedRunID].compactMap { $0 })
        let previousRunIDs = Set(
            [previous.activeRun?.id, previous.recentlyEndedRun?.id].compactMap { $0 }
        )
        for removedID in previousRunIDs.subtracting(currentRunIDs)
        where try timerRepository.fetchRunIncludingSuperseded(id: removedID) == nil {
            try insertTombstone(
                entityType: .run,
                entityID: removedID,
                generation: generation,
                deletedAt: timestamp,
                conflictID: nil
            )
        }
    }

    private func insertTombstone(
        entityType: TombstoneEntityType,
        entityID: UUID,
        generation: UInt64,
        deletedAt: Date,
        conflictID: UUID?
    ) throws {
        guard generation <= UInt64(Int64.max) else { throw ContractWireError.invalidEnvelope }
        if try tombstoneRecords().contains(where: {
            $0.entityTypeRawValue == entityType.rawValue && $0.entityID == entityID
        }) {
            return
        }
        context.insert(
            PhoneEntityTombstoneRecord(
                tombstoneID: dependencies.makeUUID(),
                entityTypeRawValue: entityType.rawValue,
                entityID: entityID,
                canonicalGeneration: Int64(generation),
                deletedAt: deletedAt,
                conflictID: conflictID
            )
        )
    }

    private func tombstoneSnapshots() throws -> [EntityTombstone] {
        try tombstoneRecords().map { record in
            guard let type = TombstoneEntityType(rawValue: record.entityTypeRawValue),
                let generation = UInt64(exactly: record.canonicalGeneration)
            else { throw ContractWireError.invalidEnvelope }
            return EntityTombstone(
                entityType: type,
                entityID: record.entityID,
                canonicalGeneration: generation,
                deletedAt: record.deletedAt
            )
        }.sorted {
            if $0.canonicalGeneration != $1.canonicalGeneration {
                return $0.canonicalGeneration < $1.canonicalGeneration
            }
            if $0.entityType != $1.entityType {
                return $0.entityType.rawValue < $1.entityType.rawValue
            }
            return $0.entityID.uuidString < $1.entityID.uuidString
        }
    }

    private func persistCanonicalSnapshot(_ snapshot: TimerSnapshotEnvelope) throws {
        if try canonicalSnapshotRecords().contains(where: {
            $0.snapshotID == snapshot.ledgerHead.snapshotID
                && $0.canonicalGeneration == Int64(snapshot.ledgerHead.canonicalGeneration)
        }) {
            return
        }
        guard snapshot.ledgerHead.canonicalGeneration <= UInt64(Int64.max) else {
            throw ContractWireError.invalidEnvelope
        }
        context.insert(
            PhoneCanonicalSnapshotRecord(
                snapshotID: snapshot.ledgerHead.snapshotID,
                canonicalGeneration: Int64(snapshot.ledgerHead.canonicalGeneration),
                snapshotData: try ContractWireCodec.encodeSnapshot(snapshot),
                createdAt: dependencies.now
            )
        )
        let records = try canonicalSnapshotRecords().sorted {
            $0.canonicalGeneration < $1.canonicalGeneration
        }
        for record in records.prefix(max(0, records.count - 64)) {
            context.delete(record)
        }
        try save()
    }

    private func compactTombstones(crossedGeneration: Int64) throws {
        let crossed = try tombstoneRecords().filter {
            $0.canonicalGeneration <= crossedGeneration
        }
        for tombstone in crossed {
            if tombstone.entityTypeRawValue == TombstoneEntityType.run.rawValue,
                let run = try timerRepository.fetchRunIncludingSuperseded(id: tombstone.entityID)
            {
                let sessions = try timerRepository.fetchAllSessionsIncludingSuperseded()
                    .filter { $0.timerRunID == run.id }
                let sessionIDs = Set(sessions.map(\.id))
                for assignment in try timerRepository.fetchSessionTagAssignments()
                where sessionIDs.contains(assignment.sessionID) {
                    timerRepository.delete(assignment)
                }
                for assignment in try timerRepository.fetchRunTagAssignments(runID: run.id) {
                    timerRepository.delete(assignment)
                }
                for session in sessions { timerRepository.delete(session) }
                timerRepository.delete(run)
            }
            context.delete(tombstone)
        }
    }

    private func stableUUIDs(_ values: [UUID]) -> [UUID] {
        Array(Set(values)).sorted { $0.uuidString < $1.uuidString }
    }

    private func decodeUUIDs(_ data: Data) throws -> [UUID] {
        try ContractWireCodec.decodeCanonical([UUID].self, from: data)
    }

    private func inboxRecords() throws -> [PhoneMutationInboxRecord] {
        try context.fetch(FetchDescriptor<PhoneMutationInboxRecord>())
    }

    private func acknowledgementOutboxRecords() throws
        -> [PhoneAcknowledgementOutboxRecord]
    {
        try context.fetch(FetchDescriptor<PhoneAcknowledgementOutboxRecord>())
    }

    private func snapshotReceiptRecords() throws -> [PhoneSnapshotReceiptRecord] {
        try context.fetch(FetchDescriptor<PhoneSnapshotReceiptRecord>())
    }

    private func canonicalSnapshotRecords() throws -> [PhoneCanonicalSnapshotRecord] {
        try context.fetch(FetchDescriptor<PhoneCanonicalSnapshotRecord>())
    }

    private func conflictRecords() throws -> [PhoneTimerConflictRecord] {
        try context.fetch(FetchDescriptor<PhoneTimerConflictRecord>())
    }

    private func conflictMutationRecords() throws -> [PhoneConflictMutationRecord] {
        try context.fetch(FetchDescriptor<PhoneConflictMutationRecord>())
    }

    private func tombstoneRecords() throws -> [PhoneEntityTombstoneRecord] {
        try context.fetch(FetchDescriptor<PhoneEntityTombstoneRecord>())
    }

    private func save() throws {
        #if DEBUG
            try beforeSave?()
        #endif
        try context.save()
    }
}
