import SwiftUI

@main
struct ConnectivitySpikePhoneApp: App {
    @StateObject private var controller = SpikeConnectivityController.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Section("Connection") {
                        #if targetEnvironment(simulator)
                        Label(
                            "UI test mode; transport requires paired hardware",
                            systemImage: "hammer"
                        )
                        .font(.caption)
                        #endif
                        LabeledContent("Session", value: controller.activationLabel)
                            .accessibilityIdentifier("phone-session-status")
                            .accessibilityLabel("Session")
                            .accessibilityValue(controller.activationLabel)
                        LabeledContent(
                            "Paired Watch",
                            value: controller.isPaired ? "Yes" : "No"
                        )
                        .accessibilityIdentifier("paired-watch-status")
                        .accessibilityLabel("Paired Watch")
                        .accessibilityValue(controller.isPaired ? "Yes" : "No")
                        LabeledContent(
                            "Watch app",
                            value: controller.isCounterpartAppInstalled
                                ? "Installed" : "Not installed"
                        )
                        .accessibilityIdentifier("watch-install-status")
                        .accessibilityLabel("Watch app")
                        .accessibilityValue(
                            controller.isCounterpartAppInstalled
                                ? "Installed" : "Not installed"
                        )
                        LabeledContent(
                            "Reachable",
                            value: controller.isReachable ? "Yes" : "No"
                        )
                        .accessibilityIdentifier("phone-reachability-status")
                        .accessibilityLabel("Reachable")
                        .accessibilityValue(controller.isReachable ? "Yes" : "No")
                        LabeledContent(
                            "Generation",
                            value: String(
                                controller.state.canonicalSnapshot.canonicalGeneration
                            )
                        )
                        .accessibilityIdentifier("phone-generation")
                        .accessibilityLabel("Generation")
                        .accessibilityValue(
                            String(controller.state.canonicalSnapshot.canonicalGeneration)
                        )
                    }

                    Section("Durable state") {
                        LabeledContent(
                            "Inbox records",
                            value: String(controller.state.inbox.count)
                        )
                        .accessibilityIdentifier("phone-inbox-count")
                        .accessibilityLabel("Inbox records")
                        .accessibilityValue(String(controller.state.inbox.count))
                        LabeledContent(
                            "Terminal receipts",
                            value: String(
                                controller.state.inbox.filter {
                                    $0.status == .terminal
                                }.count
                            )
                        )
                        .accessibilityIdentifier("phone-terminal-receipt-count")
                        .accessibilityLabel("Terminal receipts")
                        .accessibilityValue(
                            String(
                                controller.state.inbox.filter {
                                    $0.status == .terminal
                                }.count
                            )
                        )
                        LabeledContent(
                            "Snapshot receipts",
                            value: String(controller.state.receivedSnapshotReceipts.count)
                        )
                        .accessibilityIdentifier("phone-snapshot-receipt-count")
                        .accessibilityLabel("Snapshot receipts")
                        .accessibilityValue(
                            String(controller.state.receivedSnapshotReceipts.count)
                        )
                        LabeledContent(
                            "Duplicate deliveries",
                            value: String(
                                controller.state.events.filter {
                                    $0.code == "phone_duplicate_received"
                                }.count
                            )
                        )
                        .accessibilityIdentifier("phone-duplicate-delivery-count")
                        .accessibilityLabel("Duplicate deliveries")
                        .accessibilityValue(
                            String(
                                controller.state.events.filter {
                                    $0.code == "phone_duplicate_received"
                                }.count
                            )
                        )
                        LabeledContent(
                            "Blocked",
                            value: controller.state.mutationBlocked ? "Yes" : "No"
                        )
                        .accessibilityIdentifier("phone-mutation-blocked")
                        .accessibilityLabel("Mutation blocked")
                        .accessibilityValue(
                            controller.state.mutationBlocked ? "Yes" : "No"
                        )
                    }

                    Section("Probe controls") {
                        Toggle(
                            "Hold Inbox Before Apply",
                            isOn: $controller.holdInboxBeforeApply
                        )
                        Toggle(
                            "Hold Acknowledgements",
                            isOn: $controller.holdAcknowledgements
                        )
                        Button("Publish Latest Snapshot") {
                            controller.publishCanonicalSnapshot()
                        }
                        .accessibilityIdentifier("publish-snapshot-button")
                        .disabled(!controller.canPublishSnapshot)
                        Button("Advance Synthetic Catalog Snapshot") {
                            controller.advanceSyntheticSnapshot()
                        }
                        .accessibilityIdentifier("advance-snapshot-button")
                        .disabled(!controller.canPublishSnapshot)
                        Button("Retry Durable Acknowledgements") {
                            controller.retryPendingTransfers()
                        }
                        Button("Prepare Evidence Export") {
                            controller.exportEvidence()
                        }
                        if let evidenceURL = controller.evidenceURL {
                            ShareLink(item: evidenceURL) {
                                Label("Share Evidence JSON", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button("Reset Synthetic Probe", role: .destructive) {
                            controller.resetProbeState()
                        }
                        .accessibilityIdentifier("reset-phone-probe-button")
                    }

                    if let errorCode = controller.lastErrorCode {
                        Section("Last error") {
                            Text(errorCode)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }

                    Section("Content-free evidence") {
                        ForEach(controller.state.events.suffix(30).reversed()) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.code)
                                    .font(.system(.caption, design: .monospaced))
                                Text(event.at, format: .dateTime.hour().minute().second())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("WC Probe")
            }
        }
    }
}
