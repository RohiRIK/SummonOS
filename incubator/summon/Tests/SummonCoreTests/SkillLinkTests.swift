import Foundation
import Testing
@testable import SummonCore

@Suite("Linking shipped skills into every agent")
struct SkillLinkTests {
    let fm = FileManager.default

    func makeSource() throws -> (home: URL, source: URL) {
        let home = try makeTempHome()
        let source = home.appendingPathComponent("share/summon/skills")
        for name in ["summon", "mac-app"] {
            try fm.createDirectory(at: source.appendingPathComponent(name), withIntermediateDirectories: true)
            try Data("---\nname: \(name)\n---\n".utf8).write(to: source.appendingPathComponent("\(name)/SKILL.md"))
        }
        try Data().write(to: source.appendingPathComponent("README.txt")) // not a skill: skipped
        return (home, source)
    }

    @Test func linksEverySkillIntoEveryAgentFolder() throws {
        let (home, source) = try makeSource()
        let result = try SkillLinker(home: home).link(from: source)
        #expect(result.linked.count == 2 * SkillLinker.agentFolders.count)
        #expect(result.kept.isEmpty)
        for folder in SkillLinker.agentFolders {
            let link = home.appendingPathComponent(folder).appendingPathComponent("summon")
            #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == source.appendingPathComponent("summon").path)
        }
        // Antigravity reads ~/.gemini/config/skills (verified with agy 1.4.2), not ~/.antigravity.
        #expect(SkillLinker.agentFolders.contains(".gemini/config/skills"))
        #expect(SkillLinker.agentFolders.contains(".pi/agent/skills"))
    }

    @Test func relinkingIsIdempotentAndRepointsOldLinks() throws {
        let (home, source) = try makeSource()
        let linker = SkillLinker(home: home)
        let stale = home.appendingPathComponent(".claude/skills/summon")
        try fm.createDirectory(at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: stale.path, withDestinationPath: "/old/Summon.app/skills/summon")
        _ = try linker.link(from: source)
        let again = try linker.link(from: source)
        #expect(again.linked.count == 2 * SkillLinker.agentFolders.count)
        #expect(try fm.destinationOfSymbolicLink(atPath: stale.path) == source.appendingPathComponent("summon").path)
    }

    @Test func theUsersOwnFolderIsLeftAlone() throws {
        let (home, source) = try makeSource()
        let own = home.appendingPathComponent(".codex/skills/summon")
        try fm.createDirectory(at: own, withIntermediateDirectories: true)
        let result = try SkillLinker(home: home).link(from: source)
        #expect(result.kept == [own.path])
        var isDirectory: ObjCBool = false
        #expect(fm.fileExists(atPath: own.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect((try? fm.destinationOfSymbolicLink(atPath: own.path)) == nil)
    }

    @Test func skillFileListsEveryShippedSkill() throws {
        let (_, source) = try makeSource()
        let lines = SkillLinker.skillFiles(in: source)
        #expect(lines == [source.appendingPathComponent("mac-app/SKILL.md").path, source.appendingPathComponent("summon/SKILL.md").path])
    }
}
