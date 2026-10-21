#if canImport(Darwin)
import CoreFoundation
import Foundation

/// The real preferences system. Every read and write goes through CFPreferences, never plist files
/// (cfprefsd caches them and would overwrite a direct edit). ADR D1.
public struct CFPreferencesStore: PreferencesStore {
    public init() {}

    /// `NSGlobalDomain` is `kCFPreferencesAnyApplication` (`-g`) in CFPreferences.
    static func application(_ appID: String) -> CFString {
        appID == Backend.globalDomain ? kCFPreferencesAnyApplication : appID as CFString
    }

    static func host(_ host: PreferenceHost) -> CFString {
        host == .anyHost ? kCFPreferencesAnyHost : kCFPreferencesCurrentHost
    }

    public func isForced(_ key: String, appID: String) throws -> Bool {
        CFPreferencesAppValueIsForced(key as CFString, Self.application(appID))
    }

    public func copyValue(_ key: String, appID: String, host: PreferenceHost) throws -> TypedValue? {
        guard let value = CFPreferencesCopyValue(
            key as CFString, Self.application(appID), kCFPreferencesCurrentUser, Self.host(host)) else { return nil }
        return try PlistBridge.typed(from: value)
    }

    public func copyAppValue(_ key: String, appID: String) throws -> TypedValue? {
        guard let value = CFPreferencesCopyAppValue(key as CFString, Self.application(appID)) else { return nil }
        return try PlistBridge.typed(from: value)
    }

    public func setValue(_ value: TypedValue?, key: String, appID: String, host: PreferenceHost) throws {
        let object: CFPropertyList? = value.map { Self.cfObject($0.value) }
        CFPreferencesSetValue(key as CFString, object, Self.application(appID), kCFPreferencesCurrentUser, Self.host(host))
    }

    public func synchronize(appID: String, host: PreferenceHost) throws {
        let ok = host == .anyHost
            ? CFPreferencesAppSynchronize(Self.application(appID))
            : CFPreferencesSynchronize(Self.application(appID), kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard ok else {
            throw MacCtlError.commandFailed(command: "CFPreferencesSynchronize \(appID)", exitCode: 1,
                                            stderr: "cfprefsd did not accept the change")
        }
    }

    /// Rebuilds the exact CF type: `kCFBooleanTrue`/`False` for bools, SInt64 CFNumber for ints,
    /// Float64 CFNumber for reals.
    static func cfObject(_ value: Value) -> CFPropertyList {
        switch value {
        case .bool(let b): return (b ? kCFBooleanTrue : kCFBooleanFalse)!
        case .int(let i): return NSNumber(value: Int64(i))
        case .double(let d): return NSNumber(value: d)
        case .string(let s): return s as NSString
        case .data(let d): return d as NSData
        case .date(let d): return d as NSDate
        case .array(let a): return a.map { cfObject($0) } as NSArray
        case .dictionary(let d):
            let dict = NSMutableDictionary()
            for (key, item) in d { dict[key] = cfObject(item) }
            return dict
        }
    }
}
#endif
