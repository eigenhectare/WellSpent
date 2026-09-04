import AppIntents
import Foundation
import WellSpentWatchStore

struct WellSpentWatchProjectEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "WellSpent Project"
    static let defaultQuery = WellSpentWatchProjectQuery()
    let id: UUID
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

struct WellSpentWatchProjectQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [WellSpentWatchProjectEntity] {
        try await choices().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [WellSpentWatchProjectEntity] {
        try await choices().filter { $0.displayName.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [WellSpentWatchProjectEntity] {
        try await choices()
    }

    @MainActor
    private func choices() throws -> [WellSpentWatchProjectEntity] {
        try WatchWidgetSnapshotReader().readProjectChoices().enumerated().map { index, project in
            WellSpentWatchProjectEntity(
                id: project.id, displayName: project.name ?? String(localized: "Project \(index + 1)"))
        }
    }
}

protocol WellSpentWatchActionIntent: AppIntent {
    var systemRequest: WatchSystemRequest { get }
}

extension WellSpentWatchActionIntent {
    static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try WatchSystemActionDispatcher.perform(systemRequest)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StartWellSpentWatchTimerIntent: WellSpentWatchActionIntent {
    static let supportedModes: IntentModes = .foreground
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let title: LocalizedStringResource = "Start WellSpent Timer"
    static let description = IntentDescription("Start a saved timer for a cached project on your Apple Watch.")
    @Parameter(title: "Project") var project: WellSpentWatchProjectEntity

    static var parameterSummary: some ParameterSummary { Summary("Start \(\.$project)") }
    var systemRequest: WatchSystemRequest { .init(action: .start, projectID: project.id) }
}

struct PauseWellSpentWatchTimerIntent: WellSpentWatchActionIntent {
    static let supportedModes: IntentModes = .foreground
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let title: LocalizedStringResource = "Pause WellSpent Timer"
    static let description = IntentDescription("Pause counted time for the current Watch timer.")
    var systemRequest: WatchSystemRequest { .init(action: .pause) }
}

struct ResumeWellSpentWatchTimerIntent: WellSpentWatchActionIntent {
    static let supportedModes: IntentModes = .foreground
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let title: LocalizedStringResource = "Resume WellSpent Timer"
    static let description = IntentDescription("Resume counted time for the paused Watch timer.")
    var systemRequest: WatchSystemRequest { .init(action: .resume) }
}

struct SwitchWellSpentWatchProjectIntent: WellSpentWatchActionIntent {
    static let supportedModes: IntentModes = .foreground
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let title: LocalizedStringResource = "Switch WellSpent Project"
    static let description = IntentDescription("Save the current run and start a different project at one timestamp.")
    @Parameter(title: "Project") var project: WellSpentWatchProjectEntity

    static var parameterSummary: some ParameterSummary { Summary("Switch to \(\.$project)") }
    var systemRequest: WatchSystemRequest { .init(action: .switchProject, projectID: project.id) }
}

struct EndWellSpentWatchTimerIntent: WellSpentWatchActionIntent {
    static let supportedModes: IntentModes = .foreground
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let title: LocalizedStringResource = "End WellSpent Timer"
    static let description = IntentDescription("End and save the current Watch run.")
    var systemRequest: WatchSystemRequest { .init(action: .end) }
}

/// Internal control intent: parameters encode the exact observed state. Siri
/// uses the named intents above, never this low-level control representation.
struct WellSpentWatchControlAction: WellSpentWatchActionIntent {
    static let supportedModes: IntentModes = .foreground
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let title: LocalizedStringResource = "WellSpent Timer Control"
    static let isDiscoverable = false
    @Parameter(title: "Action", default: "open") var action: String
    @Parameter(title: "Project Identifier") var projectID: String?
    @Parameter(title: "Observed State") var expectedContext: String?

    init() {}
    init(request: WatchSystemRequest) {
        action = request.action.rawValue
        projectID = request.projectID?.uuidString
        expectedContext = request.expectedContext
    }

    var systemRequest: WatchSystemRequest {
        // Missing/invalid preconditions may only navigate, never mutate.
        guard let operation = WatchSystemAction(rawValue: action), expectedContext != nil else {
            return .init(action: .open)
        }
        return .init(
            action: operation, projectID: projectID.flatMap(UUID.init(uuidString:)), expectedContext: expectedContext)
    }
}

struct WellSpentWatchFavoriteConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "WellSpent Timer"
    static let description = IntentDescription("Choose a favorite project, or use the most recent project.")
    @Parameter(title: "Favorite Project") var project: WellSpentWatchProjectEntity?
}

enum WatchIntentDonations {
    static func record(_ request: WatchSystemRequest) async {
        // Donated entity content is always generic; project selection resolves
        // current names through the privacy-aware query when the user opens it.
        switch request.action {
        case .start:
            guard let id = request.projectID else { return }
            let intent = StartWellSpentWatchTimerIntent()
            intent.project = WellSpentWatchProjectEntity(id: id, displayName: String(localized: "Project"))
            _ = try? await intent.donate()
        case .pause: _ = try? await PauseWellSpentWatchTimerIntent().donate()
        case .resume: _ = try? await ResumeWellSpentWatchTimerIntent().donate()
        case .switchProject:
            guard let id = request.projectID else { return }
            let intent = SwitchWellSpentWatchProjectIntent()
            intent.project = WellSpentWatchProjectEntity(id: id, displayName: String(localized: "Project"))
            _ = try? await intent.donate()
        case .end: _ = try? await EndWellSpentWatchTimerIntent().donate()
        case .open: break
        }
    }
}
