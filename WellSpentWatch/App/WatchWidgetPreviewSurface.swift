#if DEBUG
    import SwiftUI
    import WellSpentWatchStore
    import WidgetKit

    /// Renders the production widget view with fictitious data, not simulated WC.
    /// WidgetKit scheduling, tint and physical Always On remain separate gates.
    struct WatchWidgetPreviewSurface: View {
        @ObservedObject var runtime: WellSpentWatchRuntime
        @State private var proposedBounds: CGRect = .zero

        private var family: WidgetFamily {
            switch argument("-ui-test-widget-family") {
            case "circular": .accessoryCircular
            case "corner": .accessoryCorner
            case "inline": .accessoryInline
            default: .accessoryRectangular
            }
        }

        var body: some View {
            GeometryReader { geometry in
                VStack(spacing: 12) {
                    Text(verbatim: "Widget preview").font(.caption2).foregroundStyle(.secondary)
                        .unredacted()
                        .frame(minHeight: 28)
                        .accessibilityIdentifier("watch.widget-preview.bounds")
                        .accessibilityValue(
                            Text(
                                verbatim:
                                    "\(proposedBounds.minX),\(proposedBounds.minY),\(proposedBounds.width),\(proposedBounds.height)"
                            ))
                    WellSpentWatchStatusView(entry: entry, familyOverride: family)
                        .redacted(reason: runtime.forcePrivacyRedaction ? .privacy : [])
                        .frame(
                            width: family == .accessoryCircular || family == .accessoryCorner
                                ? 64 : min(180, max(1, geometry.size.width - 24)),
                            height: family == .accessoryInline ? 28 : (family == .accessoryRectangular ? 88 : 64)
                        )
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .global)
                        } action: { bounds in
                            proposedBounds = bounds
                        }
                        // Do not clip overflow: the audit must see it. The
                        // independently framed background records the actual
                        // proposed region, not a union of overflowing children.
                        .padding(5)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.gray.opacity(0.2))
                                .unredacted()
                        }
                        .accessibilityIdentifier("watch.widget-preview")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        private var entry: WellSpentWatchStatusEntry {
            let state = runtime.storeState.map { state in
                var projection = state.projection
                projection.showProjectNamesOnSystemSurfaces =
                    ProcessInfo.processInfo.arguments.contains("-ui-test-widget-names")
                return WatchWidgetState.make(
                    projection: projection, pendingSync: state.isPendingSync,
                    isBlocked: state.isBlocked, recentProjectIDs: state.recentProjectIDs)
            }
            return WellSpentWatchStatusEntry(date: .now, state: state)
        }

        private func argument(_ flag: String) -> String? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
    }
#endif
