import Foundation
import WellSpentWatchStore

enum WatchSystemAction: String, Sendable {
    case open, start, pause, resume, switchProject, end
}

struct WatchSystemRequest: Equatable, Sendable {
    let action: WatchSystemAction
    var projectID: UUID? = nil
    var expectedContext: String? = nil
}

enum WatchSystemActionError: Error, LocalizedError {
    case unavailable, setupRequired, reviewRequired, updateRequired, staleControl, busy, saveFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "Open WellSpent on your Apple Watch and try again.")
        case .setupRequired: String(localized: "Choose an active project in WellSpent on your iPhone first.")
        case .reviewRequired: String(localized: "Your time is preserved. Review it in WellSpent on your iPhone.")
        case .updateRequired: String(localized: "Update WellSpent on your iPhone and Apple Watch first.")
        case .staleControl: String(localized: "The timer changed. Open WellSpent to see its current state.")
        case .busy: String(localized: "A timer change is being saved. Try again shortly.")
        case .saveFailed: String(localized: "The timer could not be changed. Your saved time is unchanged.")
        }
    }
}

/// Foreground App Intents are registered by the Watch app. The extension has no
/// writer and fails safely if the system ever attempts extension-side execution.
@MainActor
enum WatchSystemActionDispatcher {
    static var execute: ((WatchSystemRequest) throws -> String)?

    static func perform(_ request: WatchSystemRequest) throws -> String {
        guard let execute else { throw WatchSystemActionError.unavailable }
        return try execute(request)
    }
}

struct WatchSystemControlValue: Sendable {
    let request: WatchSystemRequest
    let title: String
    let symbol: String
    let pendingSync: Bool

    static func make(state: WatchWidgetState?, favoriteID: UUID?, availableIDs: Set<UUID>) -> Self {
        guard let state else {
            return Self(
                request: .init(action: .open), title: String(localized: "Open WellSpent"), symbol: "stopwatch",
                pendingSync: false)
        }
        let action: WatchSystemAction
        let title: String
        let symbol: String
        let projectID = favoriteID ?? state.recentProjects.first?.id
        switch state.timerState {
        case .running:
            action = .pause
            title = String(localized: "Pause Timer")
            symbol = "pause.fill"
        case .paused:
            action = .resume
            title = String(localized: "Resume Timer")
            symbol = "play.fill"
        case .ready where projectID.map(availableIDs.contains) == true:
            action = .start
            title = favoriteID == nil ? String(localized: "Start Recent") : String(localized: "Start Favorite")
            symbol = "play.fill"
        case .blocked:
            action = .open
            title = String(localized: "Review on iPhone")
            symbol = "exclamationmark.bubble"
        case .updateRequired:
            action = .open
            title = String(localized: "Update WellSpent")
            symbol = "arrow.down.app"
        case .ready, .setupRequired:
            action = .open
            title = String(localized: "Choose Project")
            symbol = "folder"
        }
        guard action == .open || state.commandContext != nil else {
            return Self(
                request: .init(action: .open), title: String(localized: "Open WellSpent"), symbol: "stopwatch",
                pendingSync: state.pendingSync)
        }
        return Self(
            request: WatchSystemRequest(action: action, projectID: projectID, expectedContext: state.commandContext),
            title: title, symbol: symbol, pendingSync: state.pendingSync)
    }
}
