import Foundation

enum Shell {
    struct Failure: LocalizedError {
        let status: Int32
        let output: String

        var errorDescription: String? {
            let tail = output
                .split(separator: "\n", omittingEmptySubsequences: true)
                .suffix(3)
                .joined(separator: "\n")
            return tail.isEmpty ? "Command failed with exit code \(status)." : tail
        }
    }

    private final class Buffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
        }

        var string: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        env["GIT_TERMINAL_PROMPT"] = "0"
        return env
    }

    /// Runs a process and returns combined stdout/stderr. Throws `Failure` on non-zero exit.
    static func run(
        _ executable: String,
        _ arguments: [String],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let buffer = Buffer()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                buffer.append(chunk)
                onOutput?(String(decoding: chunk, as: UTF8.self))
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                if !rest.isEmpty {
                    buffer.append(rest)
                    onOutput?(String(decoding: rest, as: UTF8.self))
                }
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: buffer.string)
                } else {
                    continuation.resume(throwing: Failure(status: proc.terminationStatus, output: buffer.string))
                }
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
