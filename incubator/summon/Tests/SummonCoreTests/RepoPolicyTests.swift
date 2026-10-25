import Foundation
import Testing
@testable import SummonCore

@Suite("A new app gets a private repo only when the owner chose so")
struct RepoPolicyTests {
    @Test func askIsTheDefaultAndAChoiceIsKept() throws {
        let store = RepoPolicyStore(paths: SummonPaths(home: try makeTempHome()))
        #expect(store.load() == .ask)
        try store.save(.always)
        #expect(store.load() == .always)
        try store.save(.ask)
        #expect(store.load() == .ask)
    }

    @Test func reposAreAlwaysPrivate() {
        let arguments = PrivateRepoService.createArguments(RepoRequest(project: "end-of-day", owner: nil, directory: "/u/a/Summon/Apps/end-of-day"))
        #expect(arguments.contains("--private"))
        #expect(!arguments.contains("--public") && !arguments.contains("--internal"))
    }
}
