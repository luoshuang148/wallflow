import XCTest
import AppKit
import AVFoundation
@testable import WallpaperCore
@testable import WallpaperRuntime

@MainActor final class VideoPreviewTests: XCTestCase {
    func project() throws -> WallpaperProject {
        guard let folder = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else { throw XCTSkip("Set WALLPAPER_FOLDER") }
        _ = NSApplication.shared
        return try WallpaperProject.load(folder:URL(fileURLWithPath:folder))
    }
    func waitForPlayer(_ model:VideoPreviewModel) async throws -> AVQueuePlayer {
        let deadline = Date().addingTimeInterval(6)
        while model.player?.currentItem?.status != .readyToPlay && model.errorMessage == nil && Date() < deadline {
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTAssertNil(model.errorMessage)
        return try XCTUnwrap(model.player)
    }
    func testVisiblePreviewMovesSilentlyAndHiddenPreviewReleasesPlayback() async throws {
        let model = VideoPreviewModel(); defer { model.stop() }
        model.setProject(try project())
        XCTAssertNil(model.player,"A closed manager must not create a decoder")
        model.setVisible(true)
        let first = try await waitForPlayer(model)
        XCTAssertTrue(first.isMuted)
        XCTAssertEqual(first.volume,0)
        XCTAssertEqual(model.aspectRatio ?? 0,16.0/9.0,accuracy:0.01)
        try await Task.sleep(for:.milliseconds(350))
        XCTAssertGreaterThan(first.currentTime().seconds,0.1)
        model.setVisible(false)
        XCTAssertNil(model.player)
        XCTAssertNil(first.currentItem)
        XCTAssertEqual(first.rate,0)
        model.setVisible(true)
        let reopened = try await waitForPlayer(model)
        XCTAssertFalse(first === reopened)
        XCTAssertTrue(reopened.isMuted)
        model.stop()
        XCTAssertNil(model.player)
        model.setVisible(true)
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertNil(model.player,"Stopped views must not resurrect the previous project")
    }
    func testProjectSwitchReleasesOldPlayerAndKeepsOnlyLatestSelection() async throws {
        let original = try project()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.linkItem(at:URL(fileURLWithPath:original.videoPath),to:root.appendingPathComponent("video.mp4"))
        try Data(#"{"type":"video","file":"video.mp4"}"#.utf8).write(to:root.appendingPathComponent("project.json"))
        let replacement = try WallpaperProject.load(folder:root)
        let model = VideoPreviewModel(); defer { model.stop() }
        model.setVisible(true); model.setProject(original)
        let first = try await waitForPlayer(model)
        model.setProject(replacement)
        let second = try await waitForPlayer(model)
        XCTAssertFalse(first === second)
        XCTAssertNil(first.currentItem)
        let asset = try XCTUnwrap(second.currentItem?.asset as? AVURLAsset)
        XCTAssertEqual(asset.url.path,replacement.videoPath)
        model.setProject(original)
        model.setProject(nil)
        try await Task.sleep(for:.milliseconds(250))
        XCTAssertNil(model.player,"Cancelled preparation must not install a stale selection")
    }
    func testHideDuringPreparationDoesNotCreateLatePlayer() async throws {
        let model = VideoPreviewModel(); defer { model.stop() }
        model.setVisible(true); model.setProject(try project()); model.setVisible(false)
        try await Task.sleep(for:.milliseconds(350))
        XCTAssertNil(model.player)
    }
    func testMissingSourceFallsBackWithoutLeavingPlayer() async throws {
        let model = VideoPreviewModel(); defer { model.stop() }
        let missing = WallpaperProject(folderPath:"/nonexistent-preview",title:"Missing",videoPath:"/nonexistent-preview/v.mp4",previewPath:nil)
        model.setVisible(true); model.setProject(missing)
        for _ in 0..<100 where model.errorMessage == nil { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.player)
    }

    func testDroppingModelReleasesPlayerEvenIfSurfaceRetainsIt() async throws {
        var model:VideoPreviewModel? = VideoPreviewModel()
        model?.setVisible(true); model?.setProject(try project())
        let retainedPlayer = try await waitForPlayer(try XCTUnwrap(model))
        let weakModel = WeakPreviewReference(model)
        model = nil
        XCTAssertNil(weakModel.value)
        XCTAssertNil(retainedPlayer.currentItem)
        XCTAssertEqual(retainedPlayer.rate,0)
    }
    func testPreviewLoopsRealShortVideo() async throws {
        let source = try project()
        let ffmpeg = "/opt/homebrew/bin/ffmpeg"
        guard FileManager.default.isExecutableFile(atPath:ffmpeg) else { throw XCTSkip("FFmpeg required for short loop fixture") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let process = Process(); process.executableURL = URL(fileURLWithPath:ffmpeg)
        process.arguments = ["-nostdin","-v","error","-i",source.videoPath,"-t","0.4","-an","-c:v","copy",root.appendingPathComponent("video.mp4").path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0)
        try Data(#"{"type":"video","file":"video.mp4"}"#.utf8).write(to:root.appendingPathComponent("project.json"))
        let model = VideoPreviewModel(); defer { model.stop() }
        model.setVisible(true); model.setProject(try WallpaperProject.load(folder:root))
        let player = try await waitForPlayer(model)
        var previous = player.currentTime().seconds, wrapped = false
        for _ in 0..<35 {
            try await Task.sleep(for:.milliseconds(100))
            let next = player.currentTime().seconds
            if next < previous - 0.05 { wrapped = true; break }
            previous = next
        }
        XCTAssertTrue(wrapped,"The preview must advance into a second loop")
        XCTAssertTrue(player.isMuted)
    }
}

private final class WeakPreviewReference {
    weak var value: VideoPreviewModel?
    init(_ value:VideoPreviewModel?) { self.value = value }
}
