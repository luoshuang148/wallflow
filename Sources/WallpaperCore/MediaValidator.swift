import AVFoundation

public struct MediaInfo: Sendable {
    public let width: Int
    public let height: Int
    public let duration: Double
}
public enum MediaValidator {
    public static func validate(url: URL) async throws -> MediaInfo {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw WallpaperError.message(L("error.media.theVideoFileHasMovedOrCannotBe"))
        }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
            throw WallpaperError.message(L("error.media.theSystemPlayerDoesNotSupportThisVideo"))
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw WallpaperError.message(L("error.media.theFileHasNoPlayableVideoTrack")) }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let dimensions = size.applying(transform)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw WallpaperError.message(L("error.media.theVideoDurationIsInvalid")) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        _ = try await generator.image(at: .zero)
        return MediaInfo(width: Int(abs(dimensions.width)), height: Int(abs(dimensions.height)), duration: duration)
    }
}
