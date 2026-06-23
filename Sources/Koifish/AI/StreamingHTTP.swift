import Foundation

/// Shared helper for Server-Sent-Events POST requests. Sends `request`, validates
/// the status (reading the body for a useful error), then invokes `onData` for
/// each SSE `data:` payload until the stream ends.
///
/// Transient failures (HTTP 429 / 5xx, or a network blip) get **one** automatic
/// retry with a short backoff before surfacing — but only during the connect /
/// status phase, never once we've started yielding data.
enum StreamingHTTP {
    /// Number of automatic retries on a transient failure (so 2 attempts total).
    static let maxRetries = 1

    static func stream(
        _ request: URLRequest,
        onData: (String) throws -> Void
    ) async throws {
        let bytes = try await connect(request)
        for try await line in bytes.lines {
            if let payload = payload(from: line) { try onData(payload) }
        }
    }

    /// Open the request and return the byte stream of a 200 response, retrying once
    /// on a transient error. No `onData` has fired yet, so a retry here is safe.
    private static func connect(_ request: URLRequest) async throws -> URLSession.AsyncBytes {
        var attempt = 0
        while true {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AIError.malformedResponse("no HTTP response")
                }
                if http.statusCode == 200 { return bytes }

                // Drain the body so we can surface a meaningful error message.
                var body = ""
                for try await line in bytes.lines { body += line + "\n" }

                if attempt < maxRetries, isRetryable(status: http.statusCode) {
                    attempt += 1
                    let delay = retryDelay(retryAfter: http.value(forHTTPHeaderField: "Retry-After"), attempt: attempt)
                    Log.debug("HTTP \(http.statusCode) — retrying in \(delay)s (attempt \(attempt))")
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                throw AIError.http(status: http.statusCode, body: body.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch let error as AIError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Network-level failure: retry once, then surface.
                if attempt < maxRetries {
                    attempt += 1
                    Log.debug("network error — retrying (attempt \(attempt)): \(error.localizedDescription)")
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                throw AIError.network(error.localizedDescription)
            }
        }
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
