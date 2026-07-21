import Foundation
import Observation

/// Remembers speaker names across sessions so recurring people (a co-host, a
/// manager, a regular client) can be applied with one click instead of retyped.
///
/// Backed by UserDefaults — small, and it should survive relaunches.
@Observable
final class SpeakerStore {
    private static let key = "recentSpeakerNames"
    private static let limit = 24

    private(set) var recents: [String] = []

    init() {
        recents = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    /// Records a name as recently used, moving it to the front if already known.
    /// Matching is case-insensitive so "johan" doesn't create a twin of "Johan".
    func remember(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        recents.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        recents.insert(name, at: 0)
        if recents.count > Self.limit {
            recents = Array(recents.prefix(Self.limit))
        }
        persist()
    }

    func forget(_ name: String) {
        recents.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        persist()
    }

    func clear() {
        recents.removeAll()
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(recents, forKey: Self.key)
    }
}
