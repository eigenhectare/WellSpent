import SwiftUI
import WatchKit

@main
struct ConnectivitySpikeWatchApp: App {
    @WKApplicationDelegateAdaptor(ConnectivitySpikeWatchDelegate.self)
    private var applicationDelegate
    @StateObject private var controller = SpikeConnectivityController.shared

    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(spacing: 10) {
                    Text("WC Probe")
                        .font(.headline)

                    #if targetEnvironment(simulator)
                    Label("UI only", systemImage: "hammer")
                        .font(.caption2)
                    #endif

                    HStack {
                        Label(
                            controller.isReachable ? "Reachable" : "Queued",
                            systemImage: controller.isReachable
                                ? "iphone.radiowaves.left.and.right" : "arrow.up.arrow.down"
                        )
                        Spacer()
                        Text(controller.activationLabel)
                    }
                    .font(.caption2)
                    .accessibilityIdentifier("session-status")
                    .accessibilityLabel("Watch session")
                    .accessibilityValue(
                        "\(controller.activationLabel), "
                            + (controller.isReachable ? "Reachable" : "Queued")
                    )

                    Button(controller.primaryActionLabel) {
                        controller.queueNextMutation()
                    }
                    .accessibilityIdentifier("watch-primary-action")
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.state.mutationBlocked)

                    if controller.canEnd {
                        Button("Queue End", role: .destructive) {
                            controller.queueEndMutation()
                        }
                        .accessibilityIdentifier("watch-end-action")
                    }

                    Button("Retry Pending") {
                        controller.retryPendingTransfers()
                    }
                    .disabled(controller.state.outbox.isEmpty)

                    Button("Reset Probe", role: .destructive) {
                        controller.resetProbeState()
                    }
                    .accessibilityIdentifier("reset-watch-probe-button")

                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                        GridRow {
                            Text("Outbox")
                            Text(controller.state.outbox.count, format: .number)
                                .accessibilityIdentifier("watch-outbox-count")
                                .accessibilityLabel("Outbox count")
                                .accessibilityValue(String(controller.state.outbox.count))
                        }
                        GridRow {
                            Text("Acks")
                            Text(controller.state.acknowledgements.count, format: .number)
                                .accessibilityIdentifier("watch-ack-count")
                                .accessibilityLabel("Acknowledgement count")
                                .accessibilityValue(
                                    String(controller.state.acknowledgements.count)
                                )
                        }
                        GridRow {
                            Text("Gen")
                            Text(
                                String(
                                    controller.state.installedSnapshot?.canonicalGeneration ?? 0
                                )
                            )
                            .accessibilityIdentifier("watch-generation")
                            .accessibilityLabel("Installed generation")
                            .accessibilityValue(
                                String(
                                    controller.state.installedSnapshot?.canonicalGeneration ?? 0
                                )
                            )
                        }
                    }
                    .font(.caption.monospacedDigit())

                    if controller.state.mutationBlocked {
                        Label("Review on iPhone", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let errorCode = controller.lastErrorCode {
                        Text(errorCode)
                            .accessibilityIdentifier("watch-last-error")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.red)
                    }

                    ForEach(controller.state.events.suffix(8).reversed()) { event in
                        HStack {
                            Text(event.code)
                                .lineLimit(1)
                            Spacer()
                            Text(event.at, format: .dateTime.hour().minute().second())
                        }
                        .font(.system(size: 9, design: .monospaced))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

@MainActor
final class ConnectivitySpikeWatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        SpikeConnectivityController.shared.handleBackgroundTasks(backgroundTasks)
    }
}
