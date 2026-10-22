import Foundation

public struct WallpaperGroup: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

public enum LibrarySort: String, Codable, CaseIterable {
    case added, title, favoritesFirst, newest
}

public struct LibraryOrganization: Codable, Equatable {
    public var favorites: Set<String> = []
    public var groups: [WallpaperGroup] = []
    public var memberships: [String: String] = [:]
    public var sort: LibrarySort = .added
    public var customNames: [String:String] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey { case favorites, groups, memberships, sort, customNames }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try values.decodeIfPresent(Set<String>.self, forKey: .favorites) ?? []
        groups = try values.decodeIfPresent([WallpaperGroup].self, forKey: .groups) ?? []
        memberships = try values.decodeIfPresent([String: String].self, forKey: .memberships) ?? [:]
        sort = try values.decodeIfPresent(LibrarySort.self, forKey: .sort) ?? .added
        customNames = try values.decodeIfPresent([String:String].self, forKey: .customNames) ?? [:]
    }

    public mutating func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) }
        else { favorites.insert(id) }
    }

    @discardableResult
    public mutating func addGroup(_ name: String) throws -> String {
        let cleanName = try validatedName(name)
        let group = WallpaperGroup(name: cleanName)
        groups.append(group)
        return group.id
    }

    public mutating func renameGroup(_ id: String, name: String) throws {
        guard let index = groups.firstIndex(where: { $0.id == id }) else {
            throw WallpaperError.message(L("error.library.thisGroupCouldNotBeFound"))
        }
        groups[index].name = try validatedName(name, excluding: id)
    }

    private func validatedName(_ name: String, excluding id: String? = nil) throws -> String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw WallpaperError.message(L("error.library.enterAGroupName")) }
        guard !groups.contains(where: { group in
            group.id != id && group.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
        }) else { throw WallpaperError.message(L("error.library.aGroupWithThisNameAlreadyExists")) }
        return cleanName
    }

    public mutating func deleteGroup(_ id: String) {
        groups.removeAll { $0.id == id }
        memberships = memberships.filter { $0.value != id }
    }

    public mutating func removeProject(_ id: String) {
        favorites.remove(id)
        customNames.removeValue(forKey:id)
        memberships.removeValue(forKey: id)
    }

    public func displayName(for project:WallpaperProject) -> String {
        let name = customNames[project.id]?.trimmingCharacters(in:.whitespacesAndNewlines)
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? project.title
    }
    public func filterAndSort(_ projects: [WallpaperProject], query: String, favoritesOnly: Bool, groupID: String?) -> [WallpaperProject] {
        let filtered = WallpaperSearch.filter(projects, query: query, customNames:customNames).filter { project in
            (!favoritesOnly || favorites.contains(project.id)) && (groupID == nil || memberships[project.id] == groupID)
        }
        switch sort {
        case .added: return filtered
        case .newest: return Array(filtered.reversed())
        case .title:
            return filtered.enumerated().sorted { left, right in
                let comparison = displayName(for:left.element).localizedStandardCompare(displayName(for:right.element))
                return comparison == .orderedSame ? left.offset < right.offset : comparison == .orderedAscending
            }.map(\.element)
        case .favoritesFirst:
            return filtered.filter { favorites.contains($0.id) } + filtered.filter { !favorites.contains($0.id) }
        }
    }
}

public enum PlaylistMode: String, Codable, CaseIterable { case interval, dayNight }
public enum PlaylistOrder: String, Codable, CaseIterable { case sequential, random }

public struct PlaylistSettings: Codable, Equatable {
    public var enabled = false
    public var mode: PlaylistMode = .interval
    public var order: PlaylistOrder = .sequential
    public var projectIDs: [String] = []
    public var intervalMinutes: Int = 30
    public var targetDisplayID: String? = nil
    public var dayProjectID: String? = nil
    public var nightProjectID: String? = nil
    public var dayStartMinute: Int = 480
    public var nightStartMinute: Int = 1200

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, mode, order, projectIDs, intervalMinutes, targetDisplayID, dayProjectID, nightProjectID, dayStartMinute, nightStartMinute
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        mode = try values.decodeIfPresent(PlaylistMode.self, forKey: .mode) ?? .interval
        order = try values.decodeIfPresent(PlaylistOrder.self, forKey: .order) ?? .sequential
        projectIDs = try values.decodeIfPresent([String].self, forKey: .projectIDs) ?? []
        intervalMinutes = try values.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 30
        targetDisplayID = try values.decodeIfPresent(String.self, forKey: .targetDisplayID)
        dayProjectID = try values.decodeIfPresent(String.self, forKey: .dayProjectID)
        nightProjectID = try values.decodeIfPresent(String.self, forKey: .nightProjectID)
        dayStartMinute = try values.decodeIfPresent(Int.self, forKey: .dayStartMinute) ?? 480
        nightStartMinute = try values.decodeIfPresent(Int.self, forKey: .nightStartMinute) ?? 1200
    }

    public func validate(availableIDs: Set<String>) throws {
        guard enabled else { return }
        switch mode {
        case .interval:
            guard Set(projectIDs).count >= 2, projectIDs.allSatisfy({ availableIDs.contains($0) }) else {
                throw WallpaperError.message(L("error.library.rotationRequiresAtLeastTwoDifferentWallpapersStill"))
            }
            guard (1...1440).contains(intervalMinutes) else {
                throw WallpaperError.message(L("error.library.theRotationIntervalMustBeBetween1And"))
            }
        case .dayNight:
            guard let dayProjectID, let nightProjectID, availableIDs.contains(dayProjectID), availableIDs.contains(nightProjectID) else {
                throw WallpaperError.message(L("error.library.selectDaytimeAndNighttimeWallpapersThatAreStill"))
            }
            guard (0..<1440).contains(dayStartMinute), (0..<1440).contains(nightStartMinute), dayStartMinute != nightStartMinute else {
                throw WallpaperError.message(L("error.library.dayAndNightStartTimesMustBeValid"))
            }
        }
    }

    public func isDay(at date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if dayStartMinute < nightStartMinute {
            return minute >= dayStartMinute && minute < nightStartMinute
        }
        return minute >= dayStartMinute || minute < nightStartMinute
    }
}

public enum ApplicationRuleCondition: String, Codable, CaseIterable { case running, frontmost }
public enum ApplicationRuleAction: String, Codable, CaseIterable { case mute, pause, stop }

public struct ApplicationRule: Codable, Equatable, Identifiable {
    public var id: String
    public var bundleID: String
    public var name: String
    public var condition: ApplicationRuleCondition
    public var action: ApplicationRuleAction
    public var enabled: Bool

    public init(id: String = UUID().uuidString, bundleID: String, name: String, condition: ApplicationRuleCondition = .frontmost, action: ApplicationRuleAction = .pause, enabled: Bool = true) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.condition = condition
        self.action = action
        self.enabled = enabled
    }
}

public struct ApplicationEffects: Equatable {
    public var muted: Bool
    public var paused: Bool
    public var stopped: Bool

    public init(muted: Bool = false, paused: Bool = false, stopped: Bool = false) {
        self.muted = muted
        self.paused = paused
        self.stopped = stopped
    }

    public static func evaluate(_ rules: [ApplicationRule], running: Set<String>, frontmost: String?) -> ApplicationEffects {
        var effects = ApplicationEffects()
        for rule in rules where rule.enabled {
            let matches = rule.condition == .running ? running.contains(rule.bundleID) : frontmost == rule.bundleID
            guard matches else { continue }
            switch rule.action {
            case .mute: effects.muted = true
            case .pause: effects.paused = true
            case .stop: effects.stopped = true; effects.paused = true
            }
        }
        return effects
    }
}
