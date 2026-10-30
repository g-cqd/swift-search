public import AemiJSON
public import AemiJSONRPC

/// Where a connection writes its messages: a child's standard input, or a test's buffer. AemiJSONRPC's sink.
public typealias MessageSink = JSONRPCSink

/// Why a request to the language server gave no result.
public enum LanguageServerError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The server answered with a JSON-RPC error.
    case response(code: Int, message: String)
    /// No answer within the deadline.
    case timedOut(method: String, after: Duration)
    /// The server's output ended or broke before the answer.
    case connectionClosed(reason: String)
    /// No trusted sourcekit-lsp was found.
    case serverNotFound(String)
    /// The workspace root is not a directory.
    case invalidWorkspace(String)
    /// A file the request names could not be read.
    case unreadableFile(String)

    public var description: String {
        switch self {
        case .response(let code, let message): "sourcekit-lsp answered with error \(code): \(message)"
        case .timedOut(let method, let after): "sourcekit-lsp did not answer \(method) within \(after)"
        case .connectionClosed(let reason): "the connection to sourcekit-lsp closed: \(reason)"
        case .serverNotFound(let reason): "no sourcekit-lsp to run: \(reason)"
        case .invalidWorkspace(let path): "\(path) is not a directory"
        case .unreadableFile(let path): "\(path) could not be read"
        }
    }
}

/// JSON-RPC 2.0 over the base protocol's framing, on AemiJSONRPC's `JSONRPCConnection` (roadmap 0007): requests
/// matched to their responses by id, any number in flight, a deadline each.
///
/// A request given up on, at its deadline or because its caller was cancelled, is forgotten and the server is told with
/// `$/cancelRequest`. Requests the server sends the client (`window/workDoneProgress/create`,
/// `client/registerCapability`) are answered with a null result so the server never waits on the client; notifications
/// are dropped.
public final class LanguageServerConnection: Sendable {
    private let connection: JSONRPCConnection

    public init(sink: any MessageSink) {
        connection = JSONRPCConnection(sink: sink, framing: .contentLength, cancellation: .languageServer)
    }

    /// Sends `method` with `params` and returns the response's `result`.
    ///
    /// - Throws: ``LanguageServerError`` for an error response, a closed connection or the deadline; a write
    ///   failure; `CancellationError` when the caller is cancelled. A late answer to an abandoned request is dropped.
    public func request(_ method: String, _ params: JSONValue, timeout: Duration = .seconds(120)) async throws -> JSON {
        do {
            return try await connection.request(method, params, timeout: timeout)
        } catch let error as JSONRPCConnectionError {
            throw Self.languageServerError(error)
        }
    }

    /// Sends a notification: no id, no answer.
    public func notify(_ method: String, _ params: JSONValue) async throws {
        try await connection.notify(method, params)
    }

    /// Reads the server's output until it ends, delivering each response to its request.
    ///
    /// When the output ends or is not framed, every request in flight fails with
    /// ``LanguageServerError/connectionClosed(reason:)``, and so does every later one.
    @concurrent public func run(reading chunks: some AsyncSequence<[UInt8], any Error>) async {
        await connection.run(reading: chunks)
    }

    /// Returns once the server's output has ended, or the caller is cancelled.
    public func waitUntilClosed() async {
        await connection.waitUntilClosed()
    }

    private static func languageServerError(_ error: JSONRPCConnectionError) -> LanguageServerError {
        switch error {
        case .response(let error): .response(code: error.code, message: error.message)
        case .timedOut(let method, let after): .timedOut(method: method, after: after)
        case .closed(let reason):
            .connectionClosed(reason: reason == "the peer's output ended" ? "the server's output ended" : reason)
        }
    }
}
