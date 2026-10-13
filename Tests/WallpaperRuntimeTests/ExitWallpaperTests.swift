import XCTest
import AppKit
import AVFoundation
import ImageIO
@testable import WallpaperCore
@testable import WallpaperRuntime

@MainActor final class ExitWallpaperTests: XCTestCase {
    func fixture() throws -> (URL, URL, Display) {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { throw XCTSkip("Requires display") }
        let ffmpeg = "/opt/homebrew/bin/ffmpeg"
        guard FileManager.default.isExecutableFile(atPath:ffmpeg) else { throw XCTSkip("Requires FFmpeg fixture generator") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let video = root.appendingPathComponent("video.mp4")
        let process = Process(); process.executableURL = URL(fileURLWithPath:ffmpeg)
        process.arguments = ["-nostdin","-v","error","-f","lavfi","-i","color=c=red:s=320x180:d=1:r=10","-f","lavfi","-i","color=c=blue:s=320x180:d=1:r=10","-filter_complex","[0:v][1:v]concat=n=2:v=1:a=0","-c:v","libx264","-pix_fmt","yuv420p",video.path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0)
        try Data(#"{"type":"video","file":"video.mp4"}"#.utf8).write(to:root.appendingPathComponent("project.json"))
        return (root,video,Display(id:"test-screen",name:"Test",screen:screen))
    }
    func testExportsCurrentVideoFrameAndRetainsImageAfterServiceReleased() async throws {
        let (root,video,display) = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        var installed:URL?
        let keeper = StaticWallpaperKeeper(directory:root.appendingPathComponent("Stills")) { url, target, options in
            XCTAssertEqual(target.id,"test-screen")
            XCTAssertEqual(options[.allowClipping] as? Bool,true)
            installed = url
        }
        let errors = await keeper.preserve([ExitWallpaper(display:display,videoURL:video,time:CMTime(seconds:1.5,preferredTimescale:600),fit:.fill)])
        XCTAssertTrue(errors.isEmpty)
        let url = try XCTUnwrap(installed)
        let image = try XCTUnwrap(NSBitmapImageRep(data:try Data(contentsOf:url)))
        XCTAssertEqual(image.pixelsWide,320); XCTAssertEqual(image.pixelsHigh,180)
        let color = try XCTUnwrap(image.colorAt(x:160,y:90)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.blueComponent,0.8,"Must capture current blue frame, not first red frame")
        XCTAssertLessThan(color.redComponent,0.1)
        XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
    }
    func testFailedScreenDoesNotPreventOtherScreenAndLeavesNoUnusedFile() async throws {
        let (root,video,display) = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let directory = root.appendingPathComponent("Stills")
        let other = Display(id:"other",name:"Other",screen:display.screen)
        var installed:[URL] = []
        let keeper = StaticWallpaperKeeper(directory:directory) { url,target,options in
            if target.id == "test-screen" { throw WallpaperError.message("native setter failed") }
            XCTAssertEqual(options[.allowClipping] as? Bool,false)
            installed.append(url)
        }
        let errors = await keeper.preserve([
            ExitWallpaper(display:display,videoURL:video,time:.zero,fit:.fill),
            ExitWallpaper(display:other,videoURL:video,time:.zero,fit:.fit)
        ])
        XCTAssertEqual(errors.count,1); XCTAssertEqual(installed.count,1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path).count,1)
    }
    func testMissingVideoDoesNotReplaceExistingNativeWallpaper() async throws {
        let (root,_,display) = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        var changes = 0
        let keeper = StaticWallpaperKeeper(directory:root.appendingPathComponent("Stills")) { _,_,_ in changes += 1 }
        let errors = await keeper.preserve([ExitWallpaper(display:display,videoURL:root.appendingPathComponent("missing.mp4"),time:.zero,fit:.fill)])
        XCTAssertEqual(errors.count,1); XCTAssertEqual(changes,0)
    }
    func testNewSnapshotRetainsEarlierImageThatOtherSpacesMayUse() async throws {
        let (root,video,display) = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        var installed:[URL] = []
        let keeper = StaticWallpaperKeeper(directory:root.appendingPathComponent("Stills")) { url,_,_ in installed.append(url) }
        let first = await keeper.preserve([ExitWallpaper(display:display,videoURL:video,time:.zero,fit:.fill)])
        let second = await keeper.preserve([ExitWallpaper(display:display,videoURL:video,time:CMTime(seconds:1.5,preferredTimescale:600),fit:.fill)])
        XCTAssertTrue(first.isEmpty); XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(installed.count,2)
        XCTAssertNotEqual(installed[0],installed[1])
        XCTAssertTrue(FileManager.default.fileExists(atPath:installed[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:installed[1].path))
    }
    func testTerminationKeepsAssignedProjectAndSettingsAndRejectsLateApply() async throws {
        let (root,_,_) = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let project = try WallpaperProject.load(folder:root)
        var state = AppState(); state.projects = [project]; state.defaultAssignment = Assignment(projectID:project.id,fit:.fit)
        state.isMuted = false; state.manuallyPaused = true
        let store = root.appendingPathComponent("state.json"); try StateStore.save(state,to:store)
        let before = try Data(contentsOf:store)
        let model = LibraryModel(storeURL:store); defer { model.engine.stop() }
        let snapshots = model.prepareForTermination()
        XCTAssertEqual(snapshots.first?.fit,.fit)
        XCTAssertEqual(snapshots.first?.videoURL.path,project.videoPath)
        await model.apply(projectID:project.id,target:nil,fit:.fill)
        model.setMuted(true)
        await model.restore()
        XCTAssertEqual(try Data(contentsOf:store),before)
        XCTAssertTrue(model.engine.sessions.isEmpty,"No late player may appear during termination")
    }
    func testTerminationFreezesInstalledSessionAndInvalidatesPreparedChanges() async throws {
        let (root,_,_) = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let project = try WallpaperProject.load(folder:root)
        var state = AppState(); state.projects = [project]; state.defaultAssignment = Assignment(projectID:project.id,fit:.fit)
        state.isMuted = true
        state.performance.pauseWhenOccluded = false
        let store = root.appendingPathComponent("state.json"); try StateStore.save(state,to:store)
        let model = LibraryModel(storeURL:store); defer { model.engine.stop() }
        await model.restore()
        let session = try XCTUnwrap(model.engine.sessions.values.first)
        for _ in 0..<100 where session.player.currentTime().seconds < 0.2 { try await Task.sleep(for:.milliseconds(20)) }
        // A prepared but not installed fit change must not replace the desktop at quit.
        var pending = state; pending.defaultAssignment = Assignment(projectID:project.id,fit:.fill)
        let change = try await model.engine.prepare(state:pending,displays:model.displays,shouldPlay:true)
        let snapshots = model.prepareForTermination()
        XCTAssertGreaterThan(snapshots.first?.time.seconds ?? 0,0.1)
        XCTAssertEqual(snapshots.first?.fit,.fit)
        XCTAssertEqual(session.player.rate,0)
        XCTAssertThrowsError(try model.engine.commit(change,shouldPlay:true))
        model.engine.setPlaying(true)
        XCTAssertEqual(session.player.rate,0,"Occlusion and policy callbacks must not restart frozen playback")
    }
}
