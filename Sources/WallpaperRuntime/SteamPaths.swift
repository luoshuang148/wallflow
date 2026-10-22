import Foundation
import WallpaperCore

public enum SteamPaths {
    public static var steamDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
    }
    public static func contentRoots(tool: URL?) -> [URL] {
        var bases = [steamDirectory]
        if let tool { bases.append(tool.deletingLastPathComponent()) }
        // Include additional libraries explicitly registered with Steam; no disk-wide scan.
        let file = steamDirectory.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let text = try? String(contentsOf: file, encoding: .utf8), let root = try? SteamKeyValues.parse(text).object("libraryfolders") {
            for key in root.keys {
                if let path = root.object(key)?.object("path")?.value { bases.append(URL(fileURLWithPath: path)) }
            }
        }
        return bases.map { $0.appendingPathComponent("steamapps/workshop/content/431960", isDirectory: true).standardizedFileURL }
    }
    public static func discoverTool(bundle: URL = Bundle.main.bundleURL) -> URL? {
        let base = bundle.deletingLastPathComponent()
        let candidates = [base.appendingPathComponent("SteamTools/MacOS/steamcmd"),
                          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/VideoWallpaper/SteamCMD/steamcmd")]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    public static func cachedAccounts() -> [String] {
        let file = steamDirectory.appendingPathComponent("config/config.vdf")
        guard let text = try? String(contentsOf: file, encoding: .utf8), let root = try? SteamKeyValues.parse(text) else { return [] }
        // Extract names only; never publish or copy the cached credential values.
        let accounts = root.object("InstallConfigStore")?.object("Software")?.object("Valve")?.object("Steam")?.object("Accounts")
        return (accounts?.keys ?? []).filter { (try? validateAccount($0)) != nil }.sorted()
    }
    public static func validateAccount(_ name: String) throws {
        guard name.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$", options: .regularExpression) != nil else {
            throw WallpaperError.message(L("error.steam.enterYourSteamLoginAccountNameNotYour"))
        }
    }
    public static func environment(tool: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let dir = tool.deletingLastPathComponent().path
        env["DYLD_LIBRARY_PATH"] = dir; env["DYLD_FRAMEWORK_PATH"] = dir
        return env
    }
    public static func validateDownloadFolder(_ folder: URL, id: WorkshopID, roots: [URL]) throws {
        let canonical = folder.resolvingSymlinksInPath().standardizedFileURL
        guard roots.contains(where: { root in
            canonical == root.resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent(id.rawValue).standardizedFileURL
        }) else { throw WallpaperError.message(L("error.steam.steamReturnedADownloadPathOutsideTheExpected")) }
    }
    public static func folders(in root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { (try? WorkshopID($0.lastPathComponent)) != nil && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    public static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
