import Foundation
import Testing
@testable import SummonCore

@Suite("Every new app gets a private repo")
struct RepoPolicyTests {
    @Test func alwaysIsTheDefaultAndAskIsKept() throws {
        let store = RepoPolicyStore(paths: SummonPaths(home: try makeTempHome()))
        #expect(store.load() == .always)
        try store.save(.ask)
        #expect(store.load() == .ask)
        try store.save(.always)
        #expect(store.load() == .always)
    }

    @Test func reposAreAlwaysPrivate() {
        let arguments = PrivateRepoService.createArguments(RepoRequest(project: "end-of-day", owner: nil, directory: "/u/a/Summon/Apps/end-of-day"))
        #expect(arguments.contains("--private"))
        #expect(!arguments.contains("--public") && !arguments.contains("--internal"))
    }
}
