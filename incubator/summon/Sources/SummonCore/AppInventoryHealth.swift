/// Checked inventory health shared by menu badges, repair counts, and repair actions.
public struct AppInventoryHealth: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Identifiable {
        public let category: AppSectionCategory
        public let key: String
        public let name: String
        public let health: ItemHealth

        public var id: String { category.itemID(for: key) }

        public init(category: AppSectionCategory, key: String, name: String, health: ItemHealth) {
            self.category = category
            self.key = key
            self.name = name
            self.health = health
        }
    }

    public let entries: [Entry]
    public let repairCount: Int
    public let advisoryCount: Int
    public let repairPrompt: String?

    private let categoryCounts: [AppSectionCategory: Counts]
    private let menuHealth: [String: ItemHealth]

    public init(
        projects: [Project] = [],
        themes: [Theme] = [],
        artJobs: [ArtJob] = [],
        appHealth: [String: ItemHealth] = [:],
        themeHealth: [String: ItemHealth] = [:],
        artJobHealth: [String: ItemHealth] = [:]
    ) {
        var entries: [Entry] = []
        var seen: [AppSectionCategory: Set<String>] = [:]
        var counts: [AppSectionCategory: Counts] = [:]
        var total = Counts()
        var healthByID: [String: ItemHealth] = [:]
        var categoryDefects: [AppSectionCategory: [String]] = [:]
        var defects: [String] = []

        func include(category: AppSectionCategory, key: String, name: String, health: ItemHealth?) {
            guard seen[category, default: []].insert(key).inserted else { return }
            counts[category, default: Counts()].include(health)
            total.include(health)
            guard let health else { return }
            let entry = Entry(category: category, key: key, name: name, health: health)
            entries.append(entry)
            healthByID[entry.id] = health
            if health.needsRepair {
                let diagnostic = health.fixPrompt ?? "Diagnose and repair this reported defect: \(health.detail)"
                let defect = "[\(entry.id)] \(category.rawValue): \(name)\n\(diagnostic)"
                categoryDefects[category, default: []].append(defect)
                defects.append(defect)
            }
        }

        for project in projects {
            let category: AppSectionCategory
            switch project.kind {
            case .menubar: category = .panel
            case .app: category = .app
            case .cli: category = .cli
            case .screensaver: category = .screensaver
            }
            include(category: category, key: project.name, name: project.name, health: appHealth[project.name])
        }
        for theme in themes {
            include(category: .themes, key: theme.slug, name: theme.name, health: themeHealth[theme.slug])
        }
        for job in artJobs {
            include(category: .art, key: job.name, name: job.name, health: artJobHealth[job.name])
        }

        let prompt = Self.prompt(for: defects)
        for category in AppSectionCategory.allCases {
            healthByID[category.menuID] = counts[category, default: Counts()].health(
                prompt: Self.prompt(for: categoryDefects[category] ?? [])
            )
        }
        healthByID["apps"] = total.health(prompt: prompt)
        self.entries = entries
        repairCount = total.repairs
        advisoryCount = total.advisories
        repairPrompt = prompt
        categoryCounts = counts
        menuHealth = healthByID
    }

    public func repairCount(in category: AppSectionCategory) -> Int {
        categoryCounts[category]?.repairs ?? 0
    }

    public func advisoryCount(in category: AppSectionCategory) -> Int {
        categoryCounts[category]?.advisories ?? 0
    }

    public func health(forMenuID id: String) -> ItemHealth? {
        menuHealth[id]
    }

    private static func prompt(for defects: [String]) -> String? {
        guard !defects.isEmpty else { return nil }
        return """
        Repair only the \(defects.count) inventory items listed below. Do not modify themes, palettes, or assets outside the listed defects. Preserve intentional theme styling. Ask before destructive actions.

        \(defects.joined(separator: "\n\n"))
        """
    }

    private struct Counts: Sendable, Equatable {
        var inventory = 0
        var checked = 0
        var repairs = 0
        var advisories = 0
        var level: ItemHealth.Level = .healthy

        mutating func include(_ health: ItemHealth?) {
            inventory += 1
            guard let health else { return }
            checked += 1
            level = max(level, health.level)
            if health.needsRepair { repairs += 1 }
            if health.level == .advisory { advisories += 1 }
        }

        func health(prompt: String?) -> ItemHealth {
            let badge: String
            if repairs > 0 {
                badge = "\(repairs) to Fix"
            } else if advisories > 0 {
                badge = "\(advisories) to Review"
            } else if inventory == 0 {
                badge = "No Items"
            } else if checked == 0 {
                badge = "Not Checked"
            } else if checked < inventory {
                badge = "Partially Checked"
            } else {
                badge = "Healthy"
            }
            return ItemHealth(
                level: level,
                badge: badge,
                detail: "\(checked) of \(inventory) items checked: \(repairs) need repair, \(advisories) have advisories, \(checked - repairs - advisories) healthy; \(inventory - checked) unchecked.",
                fixPrompt: prompt
            )
        }
    }
}
