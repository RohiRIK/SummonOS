import Foundation
import Testing
@testable import MacAssistantCore

struct ContractsTests {
    @Test func jsonValueRoundTrips() throws {
        let value: JSONValue = ["name": "load", "count": 3, "ratio": 0.5, "ok": true, "none": nil, "list": [1, "two"]]
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
    }

    @Test func canonicalDataIsKeyOrderIndependent() throws {
        let a: JSONValue = ["b": 1, "a": ["y": 2, "x": 1]]
        let b: JSONValue = ["a": ["x": 1, "y": 2], "b": 1]
        #expect(try a.canonicalData() == b.canonicalData())
        #expect(String(decoding: try a.canonicalData(), as: UTF8.self) == #"{"a":{"x":1,"y":2},"b":1}"#)
    }

    @Test func intValueOnlyForWholeNumbers() {
        #expect(JSONValue.number(4).intValue == 4)
        #expect(JSONValue.number(4.5).intValue == nil)
        #expect(JSONValue.string("4").intValue == nil)
    }

    @Test func schemaEncodesAsJSONSchema() throws {
        let schema = Schema.object(
            ["limit": .integer(minimum: 1, maximum: 50), "sort": .string(oneOf: ["cpu", "memory"])],
            required: ["limit"]
        )
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(schema))
        #expect(json["type"] == "object")
        #expect(json["additionalProperties"] == false)
        #expect(json["properties"]?["sort"]?["enum"] == ["cpu", "memory"])
        #expect(json["properties"]?["limit"]?["maximum"] == 50)
        #expect(json["required"] == ["limit"])
        let array = Schema.array(of: .string(), maxItems: 3)
        let arrayJSON = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(array))
        #expect(arrayJSON["items"]?["type"] == "string")
        #expect(try JSONDecoder().decode(Schema.self, from: JSONEncoder().encode(schema)) == schema)
    }

    @Test(arguments: [("15", Version(15)), ("15.4", Version(15, 4)), ("26.0.1", Version(26, 0, 1))])
    func versionParses(text: String, expected: Version) {
        #expect(Version(text) == expected)
    }

    @Test(arguments: ["", "15.", "a.b", "1.2.3.4", "-1"])
    func versionRejects(text: String) {
        #expect(Version(text) == nil)
    }

    @Test func orderings() {
        #expect(Version(15, 4) < Version(26))
        #expect(Effect.read < Effect.reversibleChange && Effect.change < Effect.privileged)
        #expect(Sensitivity.low < Sensitivity.secret)
        #expect(Finding.Severity.info < Finding.Severity.problem)
    }

    @Test func descriptorRoundTrips() throws {
        let descriptor = ToolDescriptor(
            id: "health.load", version: Version(1), summary: "Load averages and CPU count",
            output: .object(["one": .number()]), effect: .read, scope: .systemStatisticsOnly,
            timeoutSeconds: 3, verification: "Values parsed from sysctl vm.loadavg"
        )
        let data = try JSONEncoder().encode(descriptor)
        #expect(try JSONDecoder().decode(ToolDescriptor.self, from: data) == descriptor)
    }
}

struct TaskStateTests {
    @Test func terminalStatesHaveNoExits() {
        for state in TaskState.allCases where state.isTerminal {
            #expect(state.allowedNext.isEmpty)
        }
    }

    @Test func everyActiveStateCanFailCancelOrBeInterrupted() {
        for state in TaskState.allCases where !state.isTerminal {
            #expect(state.canTransition(to: .failed))
            #expect(state.canTransition(to: .cancelled))
            #expect(state.canTransition(to: .interrupted))
        }
    }

    @Test func noExecutionWithoutAuthorization() {
        let reachExecuting = TaskState.allCases.filter { $0.canTransition(to: .executing) }
        #expect(reachExecuting == [.awaitingAuthorization])
    }

    @Test func refusalReportsWithoutExecuting() {
        #expect(TaskState.awaitingAuthorization.canTransition(to: .reporting))
        #expect(!TaskState.previewing.canTransition(to: .executing))
    }
}
