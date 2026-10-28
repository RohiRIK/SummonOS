import AppIntents
import SummonCore
import SummonMenuUI

// Siri, Shortcuts and Spotlight actions. They run inside Summon (launched if needed) and use its model.
// scripts/bundle.sh writes Metadata.appintents for this module, which is how macOS finds them.

@MainActor private var model: SummonModel {
    get throws {
        guard let model = AppDelegate.shared?.model else { throw SummonIntentError.notRunning }
        return model
    }
}

enum SummonIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notRunning, noItem

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notRunning: return "Summon is not running."
        case .noItem: return "That Summon menu item no longer exists."
        }
    }
}

struct AskSummonIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Summon"
    static let description = IntentDescription("Starts your agent with what you asked.")

    @Parameter(title: "Request", requestValueDialog: "What should Summon do?")
    var request: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try model.askAgent(prompt: request)
        return .result(dialog: "Asked your agent.")
    }
}

struct PendingUpdatesIntent: AppIntent {
    static let title: LocalizedStringResource = "What Needs Updating"
    static let description = IntentDescription("Lists what has a newer version: Summon, agents, Homebrew, bun, npm and macOS.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let model = try model
        if model.lastUpdateCheck.map({ Date().timeIntervalSince($0) > 3600 }) ?? true {
            await model.checkForUpdates(quiet: true)
        }
        let pending = model.pendingUpdates
        return .result(value: pending.map(\.name), dialog: "\(SoftwareUpdate.spoken(pending))")
    }
}

struct UpdateAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Everything"
    static let description = IntentDescription("Installs every pending command-line update and shows the Updates window.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try model
        let list = model.pendingUpdates.filter { $0.command != nil }
        model.install(list)
        AppDelegate.shared?.activity.requestUpdates()
        return .result(dialog: list.isEmpty ? "Nothing to install." : "Updating \(list.count) now.")
    }
}

struct MacStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "How's My Mac"
    static let description = IntentDescription("Battery, free space, network and recent crashes.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = try model
        let snapshot = await MacContextProbe.snapshot(paths: model.paths, tools: ToolLocator.live(), hidden: [])
        return .result(value: snapshot.spoken, dialog: "\(snapshot.spoken)")
    }
}

struct MenuItemEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Summon Menu Item"
    static let defaultQuery = MenuItemQuery()

    let id: String
    let label: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(label)") }
}

struct MenuItemQuery: EntityStringQuery {
    @MainActor private var runnable: [MenuItem] {
        (AppDelegate.shared?.model.menu.items ?? []).filter { $0.action != nil }
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [MenuItemEntity] {
        runnable.filter { identifiers.contains($0.id) }.map { MenuItemEntity(id: $0.id, label: $0.label) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [MenuItemEntity] {
        runnable.filter { $0.label.localizedCaseInsensitiveContains(string) }.map { MenuItemEntity(id: $0.id, label: $0.label) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MenuItemEntity] {
        runnable.map { MenuItemEntity(id: $0.id, label: $0.label) }
    }
}

struct RunMenuItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Summon Menu Item"
    static let description = IntentDescription("Runs an item from the Summon menu.")

    @Parameter(title: "Item")
    var item: MenuItemEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try model
        guard let found = model.menu.item(item.id), found.action != nil else { throw SummonIntentError.noItem }
        model.run(found)
        return .result(dialog: "Running \(found.label).")
    }
}

struct SummonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskSummonIntent(), phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) something"],
                    shortTitle: "Ask Summon", systemImageName: "sparkles")
        AppShortcut(intent: PendingUpdatesIntent(),
                    phrases: ["What needs updating in \(.applicationName)", "Check updates in \(.applicationName)"],
                    shortTitle: "What Needs Updating", systemImageName: "arrow.down.circle")
        AppShortcut(intent: UpdateAllIntent(), phrases: ["Update everything with \(.applicationName)"],
                    shortTitle: "Update Everything", systemImageName: "arrow.down.circle.fill")
        AppShortcut(intent: MacStatusIntent(), phrases: ["How's my Mac in \(.applicationName)", "\(.applicationName) Mac status"],
                    shortTitle: "How's My Mac", systemImageName: "laptopcomputer")
        AppShortcut(intent: RunMenuItemIntent(), phrases: ["Run \(\.$item) in \(.applicationName)"],
                    shortTitle: "Run Menu Item", systemImageName: "list.bullet")
    }
}
