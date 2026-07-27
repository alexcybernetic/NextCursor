import Combine
import Foundation
import SwiftUI

/// Persists the pointer's appearance across launches.
///
/// Settings are stored locally in user defaults and nowhere else. A stored
/// payload that fails to decode, or that carries values outside the supported
/// ranges, falls back to the defaults rather than propagating a pointer the
/// user cannot see or dismiss.
// Main-thread only by construction: driven by AppKit menu actions and a
// SwiftUI form, both of which run on the main thread.
final class CursorSettingsStore: ObservableObject {
    static let storageKey = "cursor.appearance.v1"

    @Published private(set) var settings: CursorAppearanceSettings

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults

        if let data = defaults?.data(forKey: Self.storageKey),
            let decoded = try? JSONDecoder().decode(
                CursorAppearanceSettings.self,
                from: data
            )
        {
            settings = decoded.migrated().normalized()
        } else {
            settings = CursorAppearanceSettings()
        }
    }

    func binding<Value>(
        for keyPath: WritableKeyPath<CursorAppearanceSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.set($0, for: keyPath) }
        )
    }

    func set<Value>(
        _ value: Value,
        for keyPath: WritableKeyPath<CursorAppearanceSettings, Value>
    ) {
        apply { $0[keyPath: keyPath] = value }
    }

    func reset() {
        settings = CursorAppearanceSettings()
        persist()
    }

    private func apply(_ mutation: (inout CursorAppearanceSettings) -> Void) {
        var updated = settings
        mutation(&updated)
        updated = updated.normalized()
        guard updated != settings else { return }

        settings = updated
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults?.set(data, forKey: Self.storageKey)
    }
}
