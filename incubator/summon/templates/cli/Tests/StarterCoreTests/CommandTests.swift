import StarterCore
import Testing

@Suite struct CommandTests {
    @Test func defaultsToTheWorld() throws {
        #expect(try Command.parse([]) == .greet(name: "world", loud: false))
        #expect(try Command.parse([]).output == "Hello, world.")
    }

    @Test func flagsMayComeAnywhere() throws {
        #expect(try Command.parse(["ada", "--loud"]) == .greet(name: "ada", loud: true))
        #expect(try Command.parse(["--loud", "ada"]).output == "HELLO, ADA!")
    }

    @Test func helpAndVersionWin() throws {
        #expect(try Command.parse(["ada", "--help"]) == .help)
        #expect(try Command.parse(["--version"]).output.hasSuffix(Command.versionNumber))
    }

    @Test func badInputIsAUsageError() {
        #expect(throws: Command.ParseError.unknownOption("--nope")) { try Command.parse(["--nope"]) }
        #expect(throws: Command.ParseError.tooManyArguments(["b"])) { try Command.parse(["a", "b"]) }
    }
}
