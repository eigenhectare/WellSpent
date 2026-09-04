import SwiftUI

enum WatchStoreAvailability: Equatable {
    case opening
    case ready
    case unavailable
}

struct WatchFoundationView: View {
    var storeAvailability: WatchStoreAvailability = .ready
    var connectivityState: WatchConnectivityState = .activating

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text("WellSpent")
                    .font(.headline)

                Text(instructionText)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Label(statusText, systemImage: statusSymbol)
                    .font(.caption2)
                    .foregroundStyle(statusIsError ? .red : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch.foundation.screen")
    }

    private var statusText: String {
        guard storeAvailability == .ready else {
            return switch storeAvailability {
            case .opening: String(localized: "Opening local cache")
            case .ready: String(localized: "Local cache ready")
            case .unavailable: String(localized: "Local cache unavailable")
            }
        }
        return switch connectivityState {
        case .activating: String(localized: "Starting sync")
        case .available(let reachable, let pendingCount):
            if pendingCount > 0 {
                String(localized: "Pending sync (\(pendingCount))")
            } else if reachable {
                String(localized: "Up to date")
            } else {
                String(localized: "Offline · up to date")
            }
        case .blocked: String(localized: "Review required")
        case .unavailable: String(localized: "Sync unavailable")
        }
    }

    private var instructionText: String {
        if case .blocked = connectivityState {
            return String(localized: "Open iPhone to review")
        }
        return switch storeAvailability {
        case .opening: String(localized: "Finish setup on iPhone")
        case .unavailable: String(localized: "Open WellSpent on your iPhone, then try again.")
        case .ready: String(localized: "Your timer stays usable offline")
        }
    }

    private var statusSymbol: String {
        guard storeAvailability == .ready else {
            return switch storeAvailability {
            case .opening: "ellipsis.circle"
            case .ready: "checkmark.icloud"
            case .unavailable: "exclamationmark.triangle"
            }
        }
        return switch connectivityState {
        case .activating: "arrow.triangle.2.circlepath"
        case .available(_, let pendingCount):
            pendingCount > 0 ? "icloud.and.arrow.up" : "checkmark.icloud"
        case .blocked: "exclamationmark.triangle"
        case .unavailable: "icloud.slash"
        }
    }

    private var statusIsError: Bool {
        if storeAvailability == .unavailable { return true }
        if case .blocked = connectivityState { return true }
        if case .unavailable = connectivityState { return true }
        return false
    }
}
