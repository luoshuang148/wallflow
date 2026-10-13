import Foundation

public struct WallpaperProject: Codable, Identifiable, Equatable {
    public var id: String { sourceFolderPath ?? folderPath }
    public private(set) var sourceFolderPath: String? = nil
    public func identifyingSourceFolder(_ path: String?) -> WallpaperProject {
        var copy = self
        copy.sourceFolderPath = path
        return copy
    }
    public let folderPath: String
    public let title: String
    public let videoPath: String
    public let previewPath: String?
    public static func load(folder: URL) throws -> WallpaperProject {
        let base = folder.resolvingSymlinksInPath().standardizedFileURL
        let manifest = try containedFile("project.json", in: base)
        let data = try Data(contentsOf: manifest)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WallpaperError.message("project.json 格式不正确。")
        }
        guard (json["type"] as? String)?.lowercased() == "video" else {
            throw WallpaperError.message("这不是视频壁纸。请选择 Wallpaper Engine 中类型为“视频”的项目。")
        }
        guard let file = json["file"] as? String, !file.isEmpty else {
            throw WallpaperError.message("配置中缺少视频文件路径。")
        }
        let video = try containedFile(file, in: base)
        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = (json["preview"] as? String).flatMap { try? containedFile($0, in: base) }
        return WallpaperProject(folderPath: base.path, title: title.flatMap { $0.isEmpty ? nil : $0 } ?? base.lastPathComponent,
                                videoPath: video.path, previewPath: preview?.path)
    }

    private static func containedFile(_ relative: String, in base: URL) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\\") else {
            throw WallpaperError.message("配置中的文件路径无效。")
        }
        let candidate = base.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/") else {
            throw WallpaperError.message("配置引用了壁纸文件夹以外的文件。")
        }
        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw WallpaperError.message("找不到有效的文件：\(relative)")
        }
        return candidate
    }
}

public enum WallpaperError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
