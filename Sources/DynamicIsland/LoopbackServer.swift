import Foundation
import Network

/// One-shot HTTP listener on 127.0.0.1 that captures the OAuth redirect.
final class LoopbackServer: @unchecked Sendable {
    struct Callback: Sendable {
        let port: UInt16
        let query: [String: String]
    }

    struct Timeout: LocalizedError {
        var errorDescription: String? { "Sign-in timed out." }
    }

    private let queue = DispatchQueue(label: "DynamicIsland.LoopbackServer")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Callback, Error>?
    private var port: UInt16 = 0

    /// Starts listening, calls `onReady` with the bound port and waits for a request carrying `code` or `error`.
    func awaitCallback(
        timeout: TimeInterval,
        onReady: @escaping @Sendable (UInt16) -> Void
    ) async throws -> Callback {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.listener = listener

                // Handlers retain `self` until `finish` cancels the listener.
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        self.port = listener.port?.rawValue ?? 0
                        onReady(self.port)
                    case .failed(let error):
                        self.finish(.failure(error))
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { connection in
                    self.handle(connection)
                }
                listener.start(queue: self.queue)

                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(Timeout()))
                }
            }
        }
    }

    func cancel() {
        queue.async { self.finish(.failure(CancellationError())) }
    }

    // MARK: - Private (runs on `queue`)

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let query = Self.query(fromRequest: request)
            let isCallback = query["code"] != nil || query["error"] != nil

            let body = isCallback
                ? "<html><body style=\"font-family:-apple-system;text-align:center;margin-top:20vh\">"
                    + "<h2>Dynamic Island</h2><p>You can close this tab.</p></body></html>"
                : "Not found"
            let status = isCallback ? "200 OK" : "404 Not Found"
            let response = "HTTP/1.1 \(status)\r\n"
                + "Content-Type: text/html; charset=utf-8\r\n"
                + "Content-Length: \(body.utf8.count)\r\n"
                + "Connection: close\r\n\r\n"
                + body
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })

            if isCallback, let self {
                self.finish(.success(Callback(port: self.port, query: query)))
            }
        }
    }

    private func finish(_ result: Result<Callback, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        listener?.cancel()
        listener = nil
        continuation.resume(with: result)
    }

    private static func query(fromRequest request: String) -> [String: String] {
        // "GET /?code=…&state=… HTTP/1.1"
        let parts = request.split(separator: "\r\n", maxSplits: 1).first?.split(separator: " ") ?? []
        guard parts.count >= 2,
              let items = URLComponents(string: "http://127.0.0.1" + parts[1])?.queryItems else { return [:] }
        var result: [String: String] = [:]
        for item in items {
            result[item.name] = item.value ?? ""
        }
        return result
    }
}
