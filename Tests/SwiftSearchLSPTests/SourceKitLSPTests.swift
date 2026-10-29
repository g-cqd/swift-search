import Foundation
import Testing

@testable import SwiftSearchLSP

/// A package with a protocol, a conformance and calls between functions, in the temporary directory.
private struct DemoPackage {
    let root: String

    init() throws {
        root =
            FileManager.default.temporaryDirectory.appendingPathComponent("swift-search-lsp-\(UUID().uuidString)")
            .standardized.resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: root + "/Sources/Demo", withIntermediateDirectories: true)
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "Demo", targets: [.target(name: "Demo")])
        """.write(toFile: root + "/Package.swift", atomically: true, encoding: .utf8)
        try """
        protocol Greeter { func greet(name: String) -> String }

        struct English: Greeter {
            func greet(name: String) -> String { "Hello, \\(name)" }
        }

        func welcome(_ greeter: some Greeter) -> String {
            greeter.greet(name: "world")
        }

        func main() -> String { welcome(English()) }
        """.write(toFile: file, atomically: true, encoding: .utf8)
    }

    var file: String { root + "/Sources/Demo/Demo.swift" }

    func remove() { try? FileManager.default.removeItem(atPath: root) }
}

@Suite(
    .enabled(
        if: FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun"),
        "runs the toolchain's sourcekit-lsp, which xcrun finds (macOS with Xcode or the CLT)"),
    .timeLimit(.minutes(5)))
struct SourceKitLSPTests {
    @Test func `answers definition, references, implementations, callers and hover from the toolchain's server`()
        async throws
    {
        let package = try DemoPackage()
        defer { package.remove() }
        let file = package.file
        let answers = try await SourceKitLSP.withSession(workspace: package.root) { session in
            let call = SourcePosition(file: file, line: 8, column: 13)  // greeter.greet
            let requirement = SourcePosition(file: file, line: 1, column: 25)
            return (
                definition: try await session.definition(at: call),
                references: try await session.references(at: requirement),
                implementations: try await session.implementations(at: requirement),
                callers: try await session.callers(of: SourcePosition(file: file, line: 7, column: 6)),
                hover: try await session.hover(at: call)
            )
        }
        #expect(answers.definition == [SourcePosition(file: file, line: 1, column: 25)])
        #expect(answers.references == [SourcePosition(file: file, line: 8, column: 13)])
        #expect(answers.implementations == [SourcePosition(file: file, line: 4, column: 10)])
        #expect(answers.callers.map(\.symbol.name) == ["main()"])
        #expect(answers.callers.first?.callSites == [SourcePosition(file: file, line: 11, column: 25)])
        #expect(answers.hover?.contains("func greet(name: String) -> String") == true)
    }

    @Test func `refuses a workspace that is not a directory`() async throws {
        await #expect(throws: LanguageServerError.invalidWorkspace("/nonexistent/workspace")) {
            try await SourceKitLSP.withSession(workspace: "/nonexistent/workspace") { _ in () }
        }
    }

    @Test func `refuses a server that fails the trust check`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lsp-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let fake = directory + "/sourcekit-lsp"
        try "#!/bin/sh\n".write(toFile: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: fake)
        await #expect(throws: LanguageServerError.self) { try await SourceKitLSP.locate(explicit: fake) }
    }
}
