import Foundation
import SwiftData
import WellSpentShared

#if DEBUG
    @MainActor
    enum WellSpentUITestBootstrap {
        static let projectOneID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        static let projectTwoID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        static let archivedProjectID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        static let projectThreeID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        static let completedSessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        static let appStoreSessionTwoID = UUID(
            uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        )!
        static let appStoreSessionThreeID = UUID(
            uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        )!

        static func prepare(modelContainer: ModelContainer) throws {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains(where: { $0.hasPrefix("UITEST_") }) else { return }

            let context = ModelContext(modelContainer)
            if arguments.contains("UITEST_RESET_STORE") {
                for assignment in try context.fetch(FetchDescriptor<SessionTagAssignmentRecord>()) {
                    context.delete(assignment)
                }
                for tag in try context.fetch(FetchDescriptor<SessionTagRecord>()) {
                    context.delete(tag)
                }
                for session in try context.fetch(FetchDescriptor<TimeSessionRecord>()) {
                    context.delete(session)
                }
                for project in try context.fetch(FetchDescriptor<ProjectRecord>()) {
                    context.delete(project)
                }
                try context.save()
                UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.completedOnboarding)
                UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.showProjectNamesOnLockScreen)
                try? WellSpentStopHandoff.clear()
            }

            if arguments.contains("UITEST_SKIP_ONBOARDING") {
                UserDefaults.standard.set(true, forKey: AppPreferenceKeys.completedOnboarding)
            }

            let existingProjects = try context.fetch(FetchDescriptor<ProjectRecord>())
            guard existingProjects.isEmpty else { return }

            if arguments.contains("UITEST_SEED_POPULATED")
                || arguments.contains("UITEST_SEED_ACTIVE")
                || arguments.contains("UITEST_SEED_ACTIVE_LONG")
                || arguments.contains("UITEST_SEED_MALFORMED_ACTIVE")
                || arguments.contains("UITEST_SEED_ARCHIVED")
                || arguments.contains("UITEST_SEED_OVERLAP")
                || arguments.contains("UITEST_SEED_REPORTS")
                || arguments.contains("UITEST_SEED_COMPLETION")
                || arguments.contains("UITEST_SEED_APP_STORE")
                || arguments.contains("UITEST_SEED_APP_STORE_ACTIVE")
            {
                try seed(into: context, arguments: arguments)
            }
        }

        private static func seed(into context: ModelContext, arguments: [String]) throws {
            let now = Date.now
            if arguments.contains("UITEST_SEED_APP_STORE")
                || arguments.contains("UITEST_SEED_APP_STORE_ACTIVE")
            {
                try seedAppStore(into: context, now: now, arguments: arguments)
                return
            }

            let projectOne = ProjectRecord(
                id: projectOneID,
                name: "Client Redesign",
                colorToken: "blue",
                createdAt: now.addingTimeInterval(-86_400 * 30),
                updatedAt: now.addingTimeInterval(-86_400 * 30)
            )
            let projectTwo = ProjectRecord(
                id: projectTwoID,
                name: "Advisory",
                colorToken: "orange",
                createdAt: now.addingTimeInterval(-86_400 * 20),
                updatedAt: now.addingTimeInterval(-86_400 * 20)
            )
            context.insert(projectOne)
            context.insert(projectTwo)

            if arguments.contains("UITEST_SEED_ARCHIVED")
                || arguments.contains("UITEST_SEED_REPORTS")
            {
                context.insert(
                    ProjectRecord(
                        id: archivedProjectID,
                        name: "Legacy Account",
                        colorToken: "purple",
                        status: .archived,
                        createdAt: now.addingTimeInterval(-86_400 * 60),
                        updatedAt: now.addingTimeInterval(-86_400)
                    )
                )
            }

            if arguments.contains("UITEST_SEED_ACTIVE")
                || arguments.contains("UITEST_SEED_ACTIVE_LONG")
                || arguments.contains("UITEST_SEED_MALFORMED_ACTIVE")
            {
                let elapsed: TimeInterval =
                    arguments.contains("UITEST_SEED_ACTIVE_LONG")
                    ? 9 * 3_600
                    : 3_661
                context.insert(
                    TimeSessionRecord(
                        projectID: projectOneID,
                        source: .timer,
                        startAt: now.addingTimeInterval(-elapsed),
                        startTimeZoneID: TimeZone.current.identifier,
                        createdAt: now.addingTimeInterval(-elapsed),
                        updatedAt: now.addingTimeInterval(-elapsed)
                    )
                )

                if arguments.contains("UITEST_SEED_MALFORMED_ACTIVE") {
                    context.insert(
                        TimeSessionRecord(
                            projectID: projectTwoID,
                            source: .timer,
                            startAt: now.addingTimeInterval(-1_800),
                            startTimeZoneID: TimeZone.current.identifier,
                            createdAt: now.addingTimeInterval(-1_800),
                            updatedAt: now.addingTimeInterval(-1_800)
                        )
                    )
                }
            }

            if arguments.contains("UITEST_SEED_OVERLAP") {
                let intervals = overlapFixtureIntervals(referenceDate: now)
                context.insert(
                    completedSession(
                        id: completedSessionID,
                        projectID: projectOneID,
                        startAt: intervals.first.start,
                        endAt: intervals.first.end,
                        note: "Requirements review"
                    )
                )
                context.insert(
                    completedSession(
                        projectID: projectTwoID,
                        startAt: intervals.second.start,
                        endAt: intervals.second.end,
                        note: "Overlapping client call"
                    )
                )
            } else if arguments.contains("UITEST_SEED_REPORTS") {
                let calendar = Calendar.autoupdatingCurrent
                let today = calendar.startOfDay(for: now)
                context.insert(
                    completedSession(
                        id: completedSessionID,
                        projectID: projectOneID,
                        startAt: today.addingTimeInterval(9 * 3_600),
                        endAt: today.addingTimeInterval(10 * 3_600 + 30 * 60),
                        note: "Design review"
                    )
                )
                context.insert(
                    completedSession(
                        projectID: archivedProjectID,
                        startAt: today.addingTimeInterval(-30 * 60),
                        endAt: today.addingTimeInterval(30 * 60),
                        note: "Cross-midnight handoff"
                    )
                )
            } else if arguments.contains("UITEST_SEED_COMPLETION") {
                context.insert(
                    completedSession(
                        id: completedSessionID,
                        projectID: projectOneID,
                        startAt: now.addingTimeInterval(-7_200),
                        endAt: now.addingTimeInterval(-3_600),
                        note: nil
                    )
                )
            }

            try context.save()
        }

        private static func seedAppStore(
            into context: ModelContext,
            now: Date,
            arguments: [String]
        ) throws {
            let calendar = Calendar.autoupdatingCurrent
            let today = calendar.startOfDay(for: now)
            let timeZoneID = TimeZone.current.identifier
            let projects = [
                ProjectRecord(
                    id: projectOneID,
                    name: "Client Strategy",
                    colorToken: "blue",
                    emoji: "💼",
                    createdAt: today.addingTimeInterval(-86_400 * 28),
                    updatedAt: today.addingTimeInterval(-86_400 * 28)
                ),
                ProjectRecord(
                    id: projectTwoID,
                    name: "Product Launch",
                    colorToken: "orange",
                    emoji: "🚀",
                    createdAt: today.addingTimeInterval(-86_400 * 18),
                    updatedAt: today.addingTimeInterval(-86_400 * 18)
                ),
                ProjectRecord(
                    id: projectThreeID,
                    name: "Market Research",
                    colorToken: "purple",
                    emoji: "🔎",
                    createdAt: today.addingTimeInterval(-86_400 * 11),
                    updatedAt: today.addingTimeInterval(-86_400 * 11)
                ),
            ]
            projects.forEach(context.insert)

            let sessions = [
                completedSession(
                    id: completedSessionID,
                    projectID: projectOneID,
                    startAt: today.addingTimeInterval(8 * 3_600 + 40 * 60),
                    endAt: today.addingTimeInterval(10 * 3_600 + 15 * 60),
                    note: "Discovery workshop and roadmap priorities"
                ),
                completedSession(
                    id: appStoreSessionTwoID,
                    projectID: projectTwoID,
                    startAt: today.addingTimeInterval(10 * 3_600 + 30 * 60),
                    endAt: today.addingTimeInterval(12 * 3_600),
                    note: "Launch plan and stakeholder notes"
                ),
                completedSession(
                    id: appStoreSessionThreeID,
                    projectID: projectThreeID,
                    startAt: today.addingTimeInterval(13 * 3_600 + 10 * 60),
                    endAt: today.addingTimeInterval(14 * 3_600 + 35 * 60),
                    note: "Competitive research and synthesis"
                ),
                completedSession(
                    projectID: projectOneID,
                    startAt: today.addingTimeInterval(-86_400 + 14 * 3_600),
                    endAt: today.addingTimeInterval(-86_400 + 15 * 3_600 + 20 * 60),
                    note: "Proposal scope and estimate"
                ),
            ]
            sessions.forEach(context.insert)

            let tagDefinitions = SessionTagCommandService.builtInTags
            for tag in tagDefinitions {
                context.insert(
                    SessionTagRecord(
                        id: tag.id,
                        name: tag.name,
                        normalizedName: tag.name,
                        isBuiltIn: true,
                        createdAt: today,
                        updatedAt: today
                    )
                )
            }

            let tagsByName = Dictionary(uniqueKeysWithValues: tagDefinitions.map { ($0.name, $0.id) })
            for (sessionID, tagNames) in [
                (completedSessionID, ["meeting", "collaboration"]),
                (appStoreSessionTwoID, ["collaboration"]),
                (appStoreSessionThreeID, ["solo work"]),
            ] {
                for tagName in tagNames {
                    guard let tagID = tagsByName[tagName] else { continue }
                    context.insert(
                        SessionTagAssignmentRecord(
                            sessionID: sessionID,
                            tagID: tagID,
                            nameSnapshot: tagName,
                            createdAt: today
                        )
                    )
                }
            }

            if arguments.contains("UITEST_SEED_APP_STORE_ACTIVE") {
                context.insert(
                    TimeSessionRecord(
                        projectID: projectTwoID,
                        source: .timer,
                        startAt: now.addingTimeInterval(-(3_600 + 12 * 60 + 34)),
                        startTimeZoneID: timeZoneID,
                        createdAt: now.addingTimeInterval(-(3_600 + 12 * 60 + 34)),
                        updatedAt: now.addingTimeInterval(-(3_600 + 12 * 60 + 34))
                    )
                )
            }

            try context.save()
        }

        /// Keeps the overlap fixture inside the current local report day, even
        /// when the suite runs shortly after midnight. Relative offsets from
        /// `now` can otherwise place the records on yesterday's report.
        static func overlapFixtureIntervals(
            referenceDate: Date
        ) -> (first: DateInterval, second: DateInterval, manual: DateInterval) {
            let dayStart = Calendar.autoupdatingCurrent.startOfDay(for: referenceDate)
            let elapsedToday = referenceDate.timeIntervalSince(dayStart)
            let margin = elapsedToday * 0.05
            let usableDuration = elapsedToday - (2 * margin)
            let fixtureStart = dayStart.addingTimeInterval(margin)

            return (
                first: DateInterval(
                    start: fixtureStart,
                    duration: usableDuration * 0.75
                ),
                second: DateInterval(
                    start: fixtureStart.addingTimeInterval(usableDuration * 0.25),
                    duration: usableDuration * 0.75
                ),
                manual: DateInterval(
                    start: fixtureStart.addingTimeInterval(usableDuration * 0.375),
                    duration: usableDuration * 0.25
                )
            )
        }

        private static func completedSession(
            id: UUID = UUID(),
            projectID: UUID,
            startAt: Date,
            endAt: Date,
            note: String?
        ) -> TimeSessionRecord {
            TimeSessionRecord(
                id: id,
                projectID: projectID,
                source: .manual,
                startAt: startAt,
                endAt: endAt,
                startTimeZoneID: TimeZone.current.identifier,
                endTimeZoneID: TimeZone.current.identifier,
                note: note,
                createdAt: startAt,
                updatedAt: endAt
            )
        }
    }
#endif
