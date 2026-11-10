import Foundation
import PaperGlideCore
import UIKit

/// The gameplay tap path calls this and does nothing else.
enum PlayClicks {
    static var recordFlap: () -> Void = {}
}

/// Queues analytics off the frame path and reads the anonymous M3 session for sends.
@MainActor
final class AnalyticsCenter: ObservableObject {
    let client: AnalyticsClient
    private var timer: DispatchSourceTimer?
    private var crashWatch: CrashWatch?
    private var terminateObserver: NSObjectProtocol?
    private var booted = false

    init(token: @escaping () async -> String?) {
        let config = SupabaseConfig.load()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("PaperGlideAnalytics", isDirectory: true)
        let transport: AnalyticsTransport
        if config.isConfigured, let url = config.url {
            transport = SupabaseAnalyticsTransport(baseURL: url, anonKey: config.anonKey)
        } else {
            transport = IdleAnalyticsTransport()
        }
        let client = AnalyticsClient(
            store: FileAnalyticsStore(directory: folder),
            transport: transport,
            context: DeviceContext.current(),
            token: token
        )
        self.client = client
        PlayClicks.recordFlap = { [counters = client.counters] in
            counters.increment(page: "playing", control: "flap")
        }
    }

    func boot() async {
        guard !booted else { return }
        booted = true
        _ = client.beginLaunch(at: Date(), context: DeviceContext.current())
        let watch = CrashWatch()
        watch.onCrash = { [client] diagnosticID, summary, details in
            _ = client.noteMetricKit(diagnosticID: diagnosticID, summary: summary, details: details, at: Date())
        }
        watch.start()
        crashWatch = watch
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "paperGlide.analytics"))
        timer.schedule(deadline: .now() + AnalyticsClient.flushInterval, repeating: AnalyticsClient.flushInterval)
        timer.setEventHandler { [client] in
            Task { await client.flushIfDue(at: Date()) }
        }
        timer.resume()
        self.timer = timer
        terminateObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [client] _ in
            client.markTerminated()
        }
        await client.flushNow()
    }

    func record(page: String, control: String) {
        client.recordClick(page: page, control: control)
    }

    func enteredBackground() {
        Task { [client] in
            await client.enteredBackground(at: Date())
        }
    }

    func enteredForeground() {
        client.enteredForeground(at: Date())
    }

    func sendReport(category: String, text: String) async -> ReportSendResult {
        await client.sendReport(category: category, text: text)
    }
}

final class IdleAnalyticsTransport: AnalyticsTransport {
    func submitBatch(id: String, events: [QueuedEvent], accessToken: String) async throws -> AnalyticsAck {
        throw AnalyticsTransportError.unreachable
    }
}

enum DeviceContext {
    static func current() -> AnalyticsContext {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return AnalyticsContext(
            appVersion: "\(version) (\(build))",
            iosVersion: UIDevice.current.systemVersion,
            deviceModel: machine()
        )
    }

    private static func machine() -> String {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw -> String in
            let bytes = raw.bindMemory(to: CChar.self)
            guard let base = bytes.baseAddress else { return UIDevice.current.model }
            return String(cString: base)
        }
        return model.isEmpty ? UIDevice.current.model : model
    }
}
