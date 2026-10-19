import Foundation
import SummonCore

/// Agent plugins: `summon agents plugins|plugin-add` per agent, `summon plugins [install|fix]` for the shared catalog.
enum PluginCommands {
    static func installed(_ agent: Agent, _ context: Context) -> [InstalledPlugin] {
        if agent.id == "opencode" { return AgentPlugins.opencodePlugins(home: context.paths.home) }
        guard let argv = AgentPlugins.list(agent), let path = context.tools.find(agent.command) else { return [] }
        let (_, output) = AgentProbeCommands.capture(path, Array(argv.dropFirst()), context)
        return AgentPlugins.parse(agent, output: output)
    }

    static func agent(_ args: inout Arguments, usage: String) throws -> Agent {
        guard let name = args.next(), let agent = AgentRegistry.find(name) else { throw CLIError(usage) }
        return agent
    }

    /// `summon agents plugins <agent> [--json]`
    static func list(_ args: inout Arguments, _ context: Context) throws {
        let json = args.flag("--json")
        let agent = try agent(&args, usage: "Usage: summon agents plugins <agent> [--json]")
        let plugins = installed(agent, context)
        if json { return try context.printJSON(plugins) }
        if plugins.isEmpty { print("\(agent.name): no plugins") }
        for plugin in plugins {
            let state = plugin.enabled.map { $0 ? "" : " (disabled)" } ?? ""
            print("\(plugin.name)\(plugin.version.map { " \($0)" } ?? "")\(state)")
        }
    }

    /// `summon agents plugin-add <agent> <spec>`: the agent's own install (OpenCode: its config file).
    static func add(_ args: inout Arguments, _ context: Context) throws {
        let agent = try agent(&args, usage: "Usage: summon agents plugin-add <agent> <plugin>")
        guard let spec = args.next(), !spec.isEmpty else { throw CLIError("Usage: summon agents plugin-add <agent> <plugin>") }
        try add(spec, to: agent, context)
        print("Added \(spec) to \(agent.name)")
    }

    static func add(_ spec: String, to agent: Agent, _ context: Context) throws {
        if agent.id == "opencode" {
            try AgentPlugins.addOpencodePlugin(spec, home: context.paths.home)
            return
        }
        guard let argv = AgentPlugins.install(agent, spec: spec) else { throw CLIError("\(agent.name) has no plugins to add") }
        guard let path = context.tools.find(agent.command) else { throw CLIError("\(agent.name) is not installed") }
        let (ok, output) = AgentProbeCommands.capture(path, Array(argv.dropFirst()), context, includeErrors: true, limit: 300)
        guard ok else { throw CLIError("\(agent.name) could not install \(spec): \(output.trimmingCharacters(in: .whitespacesAndNewlines))") }
    }

    struct CatalogRow: Encodable {
        let plugin: CatalogPlugin
        /// Agent id → installed, for installed agents that have a build.
        let agents: [String: Bool]
    }

    @MainActor
    static func run(_ args: inout Arguments, _ context: Context) async throws {
        let installedAgents = AgentRegistry.all.filter { context.tools.find($0.command) != nil }
        switch args.next() {
        case nil, "list":
            let json = args.flag("--json")
            var cache: [String: [InstalledPlugin]] = [:]
            let rows = PluginCatalog.all.map { plugin -> CatalogRow in
                var states: [String: Bool] = [:]
                for agent in installedAgents where plugin.builds[agent.id] != nil {
                    let plugins = cache[agent.id] ?? installed(agent, context)
                    cache[agent.id] = plugins
                    states[agent.id] = plugin.isInstalled(for: agent.id, in: plugins)
                }
                return CatalogRow(plugin: plugin, agents: states)
            }
            if json { return try context.printJSON(rows) }
            for row in rows {
                let states = row.agents.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value ? "yes" : "no")" }.joined(separator: ", ")
                print("\(row.plugin.id): \(row.plugin.summary)\n  \(states.isEmpty ? "no agent here has a build" : states)")
            }
        case "install":
            guard let id = args.next(), let plugin = PluginCatalog.all.first(where: { $0.id == id }) else {
                throw CLIError("Usage: summon plugins install <id>  (known: \(PluginCatalog.all.map(\.id).joined(separator: ", ")))")
            }
            for agent in installedAgents {
                guard let build = plugin.builds[agent.id] else { continue }
                if plugin.isInstalled(for: agent.id, in: installed(agent, context)) {
                    print("\(agent.name): already has \(plugin.name)")
                    continue
                }
                do {
                    try add(build, to: agent, context)
                    print("\(agent.name): installed \(build)")
                } catch {
                    context.warn("\(agent.name): \(error)")
                }
            }
        case "fix":
            guard let id = args.next(), let plugin = PluginCatalog.all.first(where: { $0.id == id }),
                  let name = args.next(), let broken = AgentRegistry.find(name) else {
                throw CLIError("Usage: summon plugins fix <id> <agent>")
            }
            try await AgentCommands.launch(prompt: PluginCatalog.fixPrompt(plugin, agent: broken), inline: args.flag("--inline"),
                                           checkpoint: true, context)
        default:
            throw CLIError("Usage: summon plugins [list [--json] | install <id> | fix <id> <agent>]")
        }
    }
}
