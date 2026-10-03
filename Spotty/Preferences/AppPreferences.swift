import Foundation
import Observation

/// The single typed preference store. Each section persists immediately on assignment; an
/// invalid section value is ignored, keeping the previous value. Stored sections are merged
/// over current defaults when loaded, so added fields keep their defaults and unknown or
/// invalid stored data falls back to the default for that section only.
@MainActor @Observable
final class AppPreferences {
    private enum Key: String {
        case general, drawing
        var storageKey: String { "preferences.v1.\(rawValue)" }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private var storedGeneral: GeneralPreferences
    private var storedDrawing: DrawingPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedGeneral = Self.load(.general, from: defaults, default: GeneralPreferences(), isValid: \.isValid)
        storedDrawing = Self.load(.drawing, from: defaults, default: DrawingPreferences(), isValid: \.isValid,
                                  migrate: DrawingPreferences.migrate)
    }

    var general: GeneralPreferences {
        get { storedGeneral }
        set { guard newValue.isValid, newValue != storedGeneral else { return }; storedGeneral = newValue; save(newValue, .general) }
    }

    var drawing: DrawingPreferences {
        get { storedDrawing }
        set { guard newValue.isValid, newValue != storedDrawing else { return }; storedDrawing = newValue; save(newValue, .drawing) }
    }

    private func save<Value: Encodable>(_ value: Value, _ key: Key) {
        // Encoding plain Codable values cannot fail; a failure would be a programming error.
        guard let data = try? JSONEncoder().encode(value) else { return assertionFailure("Unencodable \(key)") }
        defaults.set(data, forKey: key.storageKey)
    }

    /// `migrate` rewrites stored fields from earlier builds before they are merged over the defaults.
    private static func load<Value: Codable>(_ key: Key, from defaults: UserDefaults, default base: Value,
                                             isValid: (Value) -> Bool,
                                             migrate: ([String: Any]) -> [String: Any] = { $0 }) -> Value {
        guard let data = defaults.data(forKey: key.storageKey),
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseData = try? JSONEncoder().encode(base),
              let baseObject = try? JSONSerialization.jsonObject(with: baseData),
              let mergedData = try? JSONSerialization.data(withJSONObject: merge(migrate(stored), over: baseObject)),
              let value = try? JSONDecoder().decode(Value.self, from: mergedData),
              isValid(value) else { return base }
        return value
    }

    /// Stored keys win; nested objects merge recursively so new nested fields keep defaults.
    private static func merge(_ stored: Any, over base: Any) -> Any {
        guard let stored = stored as? [String: Any], let base = base as? [String: Any] else { return stored }
        return base.merging(stored) { baseValue, storedValue in merge(storedValue, over: baseValue) }
    }
}
