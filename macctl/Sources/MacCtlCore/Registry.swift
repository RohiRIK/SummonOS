import Foundation

/// The catalog of settings, indexed by id. Duplicate ids are a programmer error (precondition).
public struct Registry: Sendable {
    /// Every setting, in catalog order.
    public let all: [Setting]
    /// Settings grouped by `Setting.domain`, each group in catalog order.
    public let byDomain: [String: [Setting]]
    private let index: [String: Setting]

    public init(_ settings: [Setting]) {
        var index: [String: Setting] = [:]
        for setting in settings {
            precondition(index[setting.id] == nil, "Duplicate setting id \(setting.id)")
            index[setting.id] = setting
        }
        self.all = settings
        self.index = index
        self.byDomain = Dictionary(grouping: settings, by: { $0.domain })
    }

    /// Domain names, sorted.
    public var domains: [String] { byDomain.keys.sorted() }

    public func contains(_ id: String) -> Bool { index[id] != nil }

    public func setting(_ id: String) throws(MacCtlError) -> Setting {
        guard let setting = index[id] else { throw MacCtlError.unknownSetting(id) }
        return setting
    }
}
