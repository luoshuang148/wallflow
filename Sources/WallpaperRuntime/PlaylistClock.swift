import Foundation
import WallpaperCore

public struct PlaylistClock {
    private var activeSettings: PlaylistSettings?
    private var deadline: Date?
    private var lastAttemptedID: String?
    private var handledBoundary: Date?

    public init() {}
    public mutating func reset() {
        activeSettings = nil
        deadline = nil
        lastAttemptedID = nil
        handledBoundary = nil
    }

    public mutating func next(settings: PlaylistSettings, availableIDs: [String], currentID: String?, now: Date,
                              calendar: Calendar = .current, canAdvance: Bool,
                              chooseIndex: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String? {
        updateSettings(settings)
        guard settings.enabled, canAdvance else { return nil }
        let available = Set(availableIDs)
        switch settings.mode {
        case .interval:
            let interval = TimeInterval(min(1440, max(1, settings.intervalMinutes)) * 60)
            guard let deadline else {
                self.deadline = now.addingTimeInterval(interval)
                return nil
            }
            guard now >= deadline else { return nil }
            // Start from this tick, so waking after a long sleep produces one attempt.
            self.deadline = now.addingTimeInterval(interval)
            var seen: Set<String> = []
            let ordered = settings.projectIDs.filter { seen.insert($0).inserted }
            let candidates = ordered.filter { available.contains($0) }
            guard !candidates.isEmpty else { return nil }
            let selected: String
            switch settings.order {
            case .sequential:
                if candidates.count == 1, candidates[0] == currentID { return nil }
                if let anchor = lastAttemptedID ?? currentID, let index = ordered.firstIndex(of: anchor) {
                    let following = (1...ordered.count).lazy.map { ordered[(index + $0) % ordered.count] }
                    guard let nextID = following.first(where: { available.contains($0) }) else { return nil }
                    selected = nextID
                } else {
                    selected = candidates[0]
                }
            case .random:
                let choices = candidates.filter { $0 != currentID }
                guard !choices.isEmpty else { return nil }
                selected = choices[min(choices.count - 1, max(0, chooseIndex(choices.count)))]
            }
            // Failed playback still counts as an attempt; the next tick can try another item.
            lastAttemptedID = selected
            return selected
        case .dayNight:
            guard let segment = Self.segment(settings: settings, now: now, calendar: calendar),
                  segment.boundary != handledBoundary,
                  let id = segment.id, available.contains(id) else { return nil }
            handledBoundary = segment.boundary
            lastAttemptedID = id
            return id
        }
    }

    public mutating func noteManualChoice(_ id: String, settings: PlaylistSettings, now: Date,
                                         calendar: Calendar = .current) {
        updateSettings(settings)
        guard settings.enabled else { return }
        lastAttemptedID = id
        switch settings.mode {
        case .interval:
            deadline = now.addingTimeInterval(TimeInterval(min(1440, max(1, settings.intervalMinutes)) * 60))
        case .dayNight:
            handledBoundary = Self.segment(settings: settings, now: now, calendar: calendar)?.boundary
        }
    }

    private mutating func updateSettings(_ settings: PlaylistSettings) {
        guard activeSettings != settings else { return }
        reset()
        activeSettings = settings
    }

    private static func segment(settings: PlaylistSettings, now: Date, calendar: Calendar) -> (boundary: Date, id: String?)? {
        guard (0..<1440).contains(settings.dayStartMinute), (0..<1440).contains(settings.nightStartMinute),
              settings.dayStartMinute != settings.nightStartMinute else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        var boundaries: [(boundary: Date, id: String?)] = []
        for start in [yesterday, today] {
            for (minute, id) in [(settings.dayStartMinute, settings.dayProjectID), (settings.nightStartMinute, settings.nightProjectID)] {
                let time = DateComponents(hour: minute / 60, minute: minute % 60, second: 0)
                if let boundary = calendar.nextDate(after: start.addingTimeInterval(-1), matching: time,
                                                    matchingPolicy: .nextTime, repeatedTimePolicy: .first), boundary <= now {
                    boundaries.append((boundary, id))
                }
            }
        }
        return boundaries.max { $0.boundary < $1.boundary }
    }
}
