import Foundation
import MetricKit
import PaperGlideCore

/// Forwards MetricKit crash diagnostics. User kills are not in these payloads;
/// the unclean-exit flag is what keeps a background termination out of the crash count.
final class CrashWatch: NSObject, MXMetricManagerSubscriber {
    var onCrash: ((String, String, String) -> Void)?

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let signal = crash.signal?.intValue
                let type = crash.exceptionType?.intValue
                let code = crash.exceptionCode?.intValue
                let reason = crash.terminationReason ?? ""
                let summary = "signal \(signal.map(String.init) ?? "none") exception \(type.map(String.init) ?? "none")/\(code.map(String.init) ?? "none") \(reason)"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let stack = String(data: crash.callStackTree.jsonRepresentation(), encoding: .utf8) ?? ""
                let diagnosticID = StableHash.fnv(summary + "\n" + String(stack.prefix(500)))
                onCrash?(diagnosticID, summary, stack)
            }
        }
    }
}
