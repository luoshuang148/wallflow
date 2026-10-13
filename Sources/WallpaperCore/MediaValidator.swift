import AVFoundation

public struct MediaInfo: Sendable {
    public let width: Int
    public let height: Int
    public let duration: Double
}
public enum MediaValidator {
    public static func validate(url: URL) async throws -> MediaInfo {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw WallpaperError.message("视频文件已移动或无法读取，请重新导入壁纸文件夹。")
        }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
            throw WallpaperError.message("系统播放器不支持这段视频的编码。")
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw WallpaperError.message("文件没有可播放的视频轨道。") }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let dimensions = size.applying(transform)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw WallpaperError.message("视频时长无效。") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        _ = try await generator.image(at: .zero)
        return MediaInfo(width: Int(abs(dimensions.width)), height: Int(abs(dimensions.height)), duration: duration)
    }
}
