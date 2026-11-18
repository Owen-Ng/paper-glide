import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Posts one batch to `submit_analytics_batch` with the anon key.
/// The service-role key is never read.
public final class SupabaseAnalyticsTransport: AnalyticsTransport {
    public let baseURL: URL
    public let anonKey: String
    public let urlSession: URLSession

    public init(baseURL: URL, anonKey: String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.urlSession = urlSession
    }

    public func submitBatch(id: String, events: [QueuedEvent], accessToken: String) async throws -> AnalyticsAck {
        let payload: [String: Any] = [
            "batch_id": id,
            "events": events.map(Self.json)
        ]
        let data = try await send(path: "/rest/v1/rpc/submit_analytics_batch", token: accessToken, body: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnalyticsTransportError.badResponse
        }
        let ok = (json["ok"] as? Bool) ?? (json["ok"] as? NSNumber)?.boolValue ?? false
        guard ok else { throw AnalyticsTransportError.badResponse }
        return (json["result"] as? String) == "duplicate" ? .duplicate : .stored
    }

    private func send(path: String, token: String, body: [String: Any]) async throws -> Data {
        let root = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        guard let url = URL(string: root + path) else { throw AnalyticsTransportError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AnalyticsTransportError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw AnalyticsTransportError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AnalyticsTransportError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else { throw AnalyticsTransportError.badResponse }
        return data
    }

    public static func json(_ event: QueuedEvent) -> [String: Any] {
        var body: [String: Any] = [
            "id": event.id,
            "kind": event.kind.rawValue,
            "occurred_at": iso8601(event.occurredAt)
        ]
        if let sessionID = event.sessionID { body["session_id"] = sessionID }
        if let page = event.page { body["page"] = page }
        if let control = event.control { body["control"] = control }
        if let count = event.count { body["count"] = count }
        if let category = event.category { body["category"] = category }
        if event.kind == .report, let text = event.text { body["text"] = text }
        if let context = event.context {
            body["app_version"] = context.appVersion
            body["ios_version"] = context.iosVersion
            body["device_model"] = context.deviceModel
        }
        if let crashKind = event.crashKind { body["crash_kind"] = crashKind }
        if let crashSummary = event.crashSummary { body["crash_summary"] = crashSummary }
        if let crashDetails = event.crashDetails { body["crash_details"] = crashDetails }
        return body
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
