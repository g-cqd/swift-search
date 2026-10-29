internal import IndexStoreSupport
internal import Subprocess

#if canImport(System)
    internal import System
#else
    internal import SystemPackage
#endif
#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

/// Runs the toolchain's sourcekit-lsp for the length of a closure.
///
/// The server is the one of the selected toolchain: `DEVELOPER_DIR`'s, else `xcrun --find sourcekit-lsp`'s, the order
/// analyzerkit's toolchain resolution follows. It must pass analyzerkit's `BinaryTrustChecker` (owned by root or the
/// user, not group- or world-writable) before it is run. The child runs in a session of its own, with the environment
/// analyzerkit's `BoundedProcess` keeps, and is stopped with its descendants when the closure returns, throws or is
/// cancelled.
public enum SourceKitLSP {
    /// How long the server has to exit after `shutdown` and `exit` before its process group is terminated.
    public static let exitGrace: Duration = .seconds(5)

    /// The trusted sourcekit-lsp to run: `explicit` when given, else the selected toolchain's.
    /// - Throws: ``LanguageServerError/serverNotFound(_:)``.
    public static func locate(explicit: String? = nil) async throws(LanguageServerError) -> String {
        var candidates: [String] = []
        if let explicit {
            candidates = [explicit]
        } else {
            let environment = ProcessInfo.processInfo.environment
            if let developer = environment["DEVELOPER_DIR"], developer.hasPrefix("/") {
                let root = developer.hasSuffix(".app") ? developer + "/Contents/Developer" : developer
                candidates += [
                    root + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp",
                    root + "/usr/bin/sourcekit-lsp",
                ]
            }
            var probe = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
            probe["HOME"] = environment["HOME"]
            probe["DEVELOPER_DIR"] = environment["DEVELOPER_DIR"]
            if let result = try? await BoundedProcess.run(
                "/usr/bin/xcrun", ["--find", "sourcekit-lsp"], environment: probe, timeout: .seconds(10),
                outputLimit: 4096), result.succeeded
            {
                let path = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
                if path.hasPrefix("/") { candidates.append(path) }
            }
        }
        var rejections: [String] = []
        for candidate in candidates {
            guard FileManager.default.isExecutableFile(atPath: candidate) else {
                rejections.append("\(candidate) is not an executable")
                continue
            }
            let trust = BinaryTrustChecker.assess(candidate)
            if trust.isTrusted { return trust.path }
            rejections.append("\(trust.path): \(trust.rejection ?? "not trusted")")
        }
        throw .serverNotFound(
            rejections.isEmpty
                ? "no toolchain selected (xcode-select, DEVELOPER_DIR) has one; pass --sourcekit-lsp"
                : rejections.joined(separator: "; "))
    }

    /// Starts sourcekit-lsp on `workspace`, initializes it, runs `body` with the session, then shuts the server down.
    ///
    /// - Parameters:
    ///   - workspace: the directory holding `Package.swift`, a `compile_commands.json` or a build server config.
    ///   - executable: a sourcekit-lsp to run instead of the toolchain's; it is trust-checked the same way.
    /// - Throws: ``LanguageServerError``; what `body` throws; a launch failure.
    public static func withSession<Result: Sendable>(
        workspace: String, executable: String? = nil,
        _ body: (LanguageServerSession) async throws -> Result
    ) async throws -> Result {
        var isDirectory: ObjCBool = false
        guard unsafe FileManager.default.fileExists(atPath: workspace, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw LanguageServerError.invalidWorkspace(workspace) }
        let server = try await locate(explicit: executable)
        var options = PlatformOptions()
        options.createSession = true
        options.teardownSequence = [.gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: .seconds(2))]
        var variables: [Environment.Key: String] = [:]
        let inherited = ProcessInfo.processInfo.environment
        let kept = BoundedProcess.scrubbedEnvironment(
            overrides: inherited["DEVELOPER_DIR"].map { ["DEVELOPER_DIR": $0] } ?? [:], source: inherited)
        for (key, value) in kept { variables[Environment.Key(stringLiteral: key)] = value }
        let outcome = try await Subprocess.run(
            .path(FilePath(server)), arguments: [], environment: .custom(variables),
            workingDirectory: FilePath(workspace), platformOptions: options, input: .inputWriter, output: .sequence,
            error: .discarded
        ) { execution in
            let connection = LanguageServerConnection(sink: InputSink(writer: execution.standardInputWriter))
            return try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await connection.run(
                        reading: execution.standardOutput.map { buffer in
                            // The bytes are copied inside the closure; the pointer does not escape it.
                            unsafe buffer.withUnsafeBytes { unsafe Array($0) }
                        })
                }
                let session = LanguageServerSession(connection: connection, workspace: workspace)
                let result: Result
                do {
                    try await session.initialize()
                    result = try await body(session)
                } catch {
                    await session.shutdown()
                    await stop(execution, group: &group)
                    throw error
                }
                await session.shutdown()
                await stop(execution, group: &group)
                return result
            }
        }
        return outcome.closureResult
    }

    /// Waits for the server's output to end after `exit`, then stops its process group if it is still running.
    private static func stop(
        _ execution: Execution<CustomWriteInput, SequenceOutput, DiscardedOutput>,
        group: inout ThrowingTaskGroup<Void, any Error>
    ) async {
        try? await execution.standardInputWriter.finish()
        group.addTask {
            try await Task.sleep(for: exitGrace)
            await execution.teardown(using: [
                .gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: .seconds(2))
            ])
        }
        // The reader ends at the server's exit; the deadline ends a server that does not exit.
        _ = try? await group.next()
        group.cancelAll()
    }
}

/// The child's standard input as a ``MessageSink``.
private struct InputSink: MessageSink {
    let writer: StandardInputWriter

    func write(_ bytes: [UInt8]) async throws {
        _ = try await writer.write(bytes)
    }
}
