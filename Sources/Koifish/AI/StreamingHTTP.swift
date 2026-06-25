import Foundation

/// Shared helper for Server-Sent-Events POST requests. Sends `request`, validates
/// the status (reading the body for a useful error), then invokes `onData` for
/// each SSE `data:` payload until the stream ends.
///
/// Transient failures — HTTP 429 / 5xx, or a network blip — get a bounded number
/// of automatic retries with a short backoff. A retry re-sends the request from
/// scratch, so it is only safe **until the consumer commits to visible output**:
/// `onData` returns `true` the first time it yields real text, and from that point
/// a blip surfaces instead of restarting (re-sending would duplicate text the user
/// already saw). The retry window therefore spans the whole *silent* warm-up —
/// TCP/TLS connect, the HTTP status, and the provider's pre-text SSE events
/// (`message_start`, `ping`, `content_block_start`, …) — which is exactly where
/// brief blips cluster, so one shouldn't cost the reply.
enum StreamingHTTP {
    /// Number of automatic retries on a transient pre-commit failure (2 attempts total).
    static let maxRetries = 1

    /// Stream `request` as SSE. `onData` receives each payload and returns whether
    /// it committed visible output — once it has, a later blip can no longer retry.
    static func stream(
        _ request: URLRequest,
        onData: (String) -> Bool
    ) async throws {
        var attempt = 0
        var committed = false
        while true {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AIError.malformedResponse("no HTTP response")
                }
                if http.statusCode != 200 {
                    let body = try await drain(bytes)
                    if attempt < maxRetries, isRetryable(status: http.statusCode) {
                        attempt += 1
                        let delay = retryDelay(retryAfter: http.value(forHTTPHeaderField: "Retry-After"), attempt: attempt)
                        Log.debug("HTTP \(http.statusCode) — retrying in \(delay)s (attempt \(attempt))")
                        try await Task.sleep(for: .seconds(delay))
                        continue
                    }
                    throw AIError.http(status: http.statusCode, body: body)
                }
                for try await line in bytes.lines {
                    if let payload = payload(from: line), onData(payload) { committed = true }
                }
                return
            } catch let error as AIError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Network blip during connect, status, or the silent warm-up. Retry
                // from scratch only before the consumer committed visible output —
                // re-sending after that would duplicate text the user already saw.
                if !committed, attempt < maxRetries {
                    attempt += 1
                    Log.debug("network blip before first token — retrying (attempt \(attempt)): \(error.localizedDescription)")
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                throw AIError.network(error.localizedDescription)
            }
        }
    }

    /// Drain a non-200 response body into a trimmed string for the error message.
    private static func drain(_ bytes: URLSession.AsyncBytes) async throws -> String {
        var body = ""
        for try await line in bytes.lines { body += line + "\n" }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a status code is worth retrying: rate limits and server errors.
    /// Pure — unit-tested.
    static func isRetryable(status: Int) -> Bool {
        status == 429 || (500...599).contains(status)
    }

    /// Seconds to wait before a retry. Honors a numeric `Retry-After` header
    /// (clamped to a sane ceiling), else a small linear backoff. Pure — unit-tested.
    static func retryDelay(retryAfter: String?, attempt: Int) -> Double {
        if let retryAfter, let seconds = Double(retryAfter.trimmingCharacters(in: .whitespaces)), seconds > 0 {
            return min(seconds, 30)
        }
        return min(8, 1.5 * Double(attempt))
    }

    /// Extract the JSON payload from one SSE line, or nil for non-data lines,
    /// the `[DONE]` sentinel, and empty/keep-alive lines. Pure — unit-tested.
    static func payload(from line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        return payload
    }

    /// Decode a JSON object payload into `[String: Any]`.
    static func jsonObject(_ payload: String) -> [String: Any]? {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }
}
