import Foundation
import Testing
import SummonCore
@testable import SummonCLI

@Suite("summon panel [--close] (panel spec C5, C6)")
struct PanelCommandTests {
    private func context(_ recorder: CallRecorder) -> Context {
        Context(paths: SummonPaths(home: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                runner: { path, args in await recorder.record(path, args); return "" },
                tools: ToolLocator(searchPath: [], isExecutable: { _ in false }))
    }

    @Test func opensThePanelInTheBackground() async throws {
        let recorder = CallRecorder()
        var args = Arguments([])
        try await PanelCommand.run(&args, context(recorder))
        #expect(await recorder.calls == [Call(path: "/usr/bin/open", args: ["-g", "summon://panel"])])
    }

    @Test func closesThePanel() async throws {
        let recorder = CallRecorder()
        var args = Arguments(["--close"])
        try await PanelCommand.run(&args, context(recorder))
        #expect(await recorder.calls == [Call(path: "/usr/bin/open", args: ["-g", "summon://panel/close"])])
    }

    @Test func twiceOpensTwiceWithoutError() async throws {
        // C6: idempotency is the app's job (PanelController.open()); the CLI just sends the route each time.
        let recorder = CallRecorder()
        for _ in 0..<2 {
            var args = Arguments([])
            try await PanelCommand.run(&args, context(recorder))
        }
        #expect(await recorder.calls.count == 2)
    }

    @Test func rejectsUnknownArguments() async throws {
        let recorder = CallRecorder()
        var args = Arguments(["--shut"])
        await #expect(throws: CLIError.self) { try await PanelCommand.run(&args, context(recorder)) }
        #expect(await recorder.calls.isEmpty)
    }

    @Test func routeIsInTheCommandCatalog() {
        #expect(CommandCatalog.find("panel")?.args == "[--close]")
    }
}

fileprivate struct Call: Equatable, Sendable {
    let path: String
    let args: [String]
}

fileprivate actor CallRecorder {
    private(set) var calls: [Call] = []
    func record(_ path: String, _ args: [String]) { calls.append(Call(path: path, args: args)) }
}
