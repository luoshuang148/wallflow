import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import WallpaperCore

public struct ExitWallpaper {
    public let display: Display
    public let videoURL: URL
    public let time: CMTime
    public let fit: FitMode
    public init(display: Display, videoURL: URL, time: CMTime, fit: FitMode) {
        self.display = display; self.videoURL = videoURL; self.time = time; self.fit = fit
    }
}

/// Hands a decoded still to macOS before the desktop video windows disappear.
@MainActor public final class StaticWallpaperKeeper {
    public typealias Installer = (URL, Display, [NSWorkspace.DesktopImageOptionKey: Any]) throws -> Void
    private let directory: URL
    private let install: Installer
    public init(directory: URL, install: Installer? = nil) {
        self.directory = directory
        self.install = install ?? { url, display, options in
            try NSWorkspace.shared.setDesktopImageURL(url, for: display.screen, options: options)
        }
    }
    public func preserve(_ wallpapers: [ExitWallpaper]) async -> [String] {
        var errors: [String] = []
        for wallpaper in wallpapers {
            var exported: URL?
            do {
                let url = try await export(wallpaper)
                exported = url
                try install(url, wallpaper.display, [
                    .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
                    .allowClipping: NSNumber(value: wallpaper.fit == .fill),
                    .fillColor: NSColor.black
                ])
                // Other Spaces can still reference earlier snapshots. Public AppKit APIs
                // cannot enumerate those references, so retain every installed image.
            } catch {
                if let exported { try? FileManager.default.removeItem(at: exported) }
                errors.append("\(wallpaper.display.name)：\(error.localizedDescription)")
            }
        }
        return errors
    }
    private func export(_ wallpaper: ExitWallpaper) async throws -> URL {
        guard FileManager.default.isReadableFile(atPath: wallpaper.videoURL.path) else {
            throw WallpaperError.message("找不到壁纸视频。")
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: wallpaper.videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds:0.1,preferredTimescale:600)
        generator.requestedTimeToleranceAfter = CMTime(seconds:0.1,preferredTimescale:600)
        let size = wallpaper.display.screen.frame.size
        let scale = wallpaper.display.screen.backingScaleFactor
        generator.maximumSize = CGSize(width:size.width * scale,height:size.height * scale)
        let time = wallpaper.time.isNumeric && wallpaper.time.seconds >= 0 ? wallpaper.time : .zero
        let image = try await withThrowingTaskGroup(of: CGImage.self) { group in
            group.addTask {
                do { return try await generator.image(at:time).image }
                catch {
                    try Task.checkCancellation()
                    // End-of-loop timestamps can fall just outside the last decodable frame.
                    return try await generator.image(at:.zero).image
                }
            }
            group.addTask {
                try await Task.sleep(for:.seconds(5))
                generator.cancelAllCGImageGeneration()
                throw WallpaperError.message("保存壁纸画面超时。")
            }
            defer { group.cancelAll(); generator.cancelAllCGImageGeneration() }
            return try await group.next()!
        }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let url = directory.appendingPathComponent("wallflow-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else {
            throw WallpaperError.message("无法保存壁纸画面。")
        }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at:url)
            throw WallpaperError.message("保存壁纸画面失败。")
        }
        return url
    }
}
