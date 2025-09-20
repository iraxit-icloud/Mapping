
import SwiftUI

struct ScanHUD: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        VStack {
            // Metrics card
            VStack(alignment: .leading, spacing: 8) {
                Text("Scan readiness \(vm.metrics.overallScore)%")
                    .font(.headline)

                // Single overall progress bar
                ProgressView(value: Double(vm.metrics.overallScore), total: 100)

                // Sub-metrics row
                HStack {
                    // Tracking submetric
                    Text("Tracking: \(vm.metrics.trackingScore)%")
                    Divider().frame(height: 12)
                    // Coverage submetric
                    Text("Coverage: \(vm.metrics.coveragePercent)%")
                    Spacer()
                    // Nice to keep raw counters for devs
                    Text("Pts: \(vm.metrics.featurePointCount)")
                    Text(String(format: "Time: %.0fs", vm.metrics.secondsElapsed))
                }
                .font(.caption)
            }

            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                if vm.scanState == .idle {
                    Button { vm.startScanningFlow() } label: { label("Start", "play.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Start scanning the environment")
                }
                if vm.scanState == .scanning {
                    Button(role: .destructive) { vm.finishAndSave() } label: { label("Finish & Save", "stop.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(!vm.metrics.meetsSaveThreshold)
                        .accessibilityHint(vm.metrics.meetsSaveThreshold ? "Stop scanning and save the map" : "Keep scanning until quality improves")
                }
                if case .saved = vm.scanState {
                    Button { /* hook to navigation entry if needed */ } label: { label("Done", "checkmark.seal.fill") }
                        .buttonStyle(.borderedProminent)
                }
                if case .error(let msg) = vm.scanState {
                    Text(msg).font(.footnote).foregroundStyle(.red)
                    Button { vm.scanState = .idle } label: { label("Retry", "arrow.counterclockwise.circle") }
                }
            }
            .padding(.bottom, 24)
        }
        .padding()
    }

    private var title: String {
        switch vm.scanState {
        case .idle: return "Ready to Scan"
        case .scanning: return "Scanning… Quality \(vm.metrics.readinessScore)%"
        case .finalizing: return "Finalizing…"
        case .saved: return "Saved"
        case .error: return "Error"
        }
    }

    private var statusText: String {
        switch vm.metrics.worldMappingStatus {
        case .notAvailable: return "N/A"
        case .limited:     return "Limited"
        case .extending:   return "Extending"
        case .mapped:      return "Mapped"
        @unknown default:  return "Unknown"
        }
    }

    private func label(_ text: String, _ system: String) -> some View {
        Label {
            Text(text).fontWeight(.semibold)
        } icon: {
            Image(systemName: system)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
