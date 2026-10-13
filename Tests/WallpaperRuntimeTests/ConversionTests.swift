import XCTest
import AppKit
import AVFoundation
@testable import WallpaperCore
@testable import WallpaperRuntime

@MainActor final class ConversionTests: XCTestCase {
    var root: URL!
    let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func fixture(_ ext: String = "webm", size: String = "64x64") async throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else { throw XCTSkip("FFmpeg required") }
        let folder = root.appendingPathComponent("source/12345")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = "video ' $()." + ext
        let args = ["-nostdin", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=\(size):rate=10:duration=0.3", "-an", "-pix_fmt", "yuv420p", "-c:v", ext == "webm" ? "libvpx" : "libx264", folder.appendingPathComponent(filename).path]
        let result = try await SteamRunner.run(executable: ffmpeg, arguments: args, timeout: 30)
        XCTAssertEqual(result.exitCode, 0, result.output)
        let json: [String: Any] = ["type":"Video", "file":filename, "title":"Conversion sample"]
        try JSONSerialization.data(withJSONObject: json).write(to: folder.appendingPathComponent("project.json"))
        return folder
    }
    func script(_ content: String) throws -> URL {
        let tool = root.appendingPathComponent(UUID().uuidString)
        try Data(("#!/bin/sh\n"+content).utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions:0o700], ofItemAtPath:tool.path)
        return tool
    }
    func testPlayableMP4UsesOriginalWithoutConverter() async throws {
        let folder = try await fixture("mp4")
        let original = try WallpaperProject.load(folder:folder)
        let prepared = try await VideoConverter.prepare(folder:folder, cacheRoot:root.appendingPathComponent("cache"), ffmpeg:URL(fileURLWithPath:"/missing/ffmpeg"))
        XCTAssertEqual(prepared,original)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("cache").path))
    }
    func testPlayableMOVIsConvertedAndPreservesTiming() async throws {
        let folder = try await fixture("mov")
        let original = try WallpaperProject.load(folder:folder)
        _ = try await MediaValidator.validate(url:URL(fileURLWithPath:original.videoPath))
        let prepared = try await VideoConverter.prepare(folder:folder, cacheRoot:root.appendingPathComponent("cache"), ffmpeg:ffmpeg)
        XCTAssertNotEqual(prepared.folderPath,original.folderPath)
        XCTAssertEqual(URL(fileURLWithPath:prepared.videoPath).pathExtension,"mp4")
        let info = try await MediaValidator.validate(url:URL(fileURLWithPath:prepared.videoPath))
        XCTAssertEqual(info.width,64); XCTAssertEqual(info.height,64); XCTAssertEqual(info.duration,0.3,accuracy:0.05)
        let probe = try await SteamRunner.run(executable:ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe"),arguments:["-v","error","-show_entries","stream=avg_frame_rate,nb_frames,codec_name","-of","json",prepared.videoPath])
        XCTAssertEqual(probe.exitCode,0,probe.output)
        let json = try JSONSerialization.jsonObject(with:Data(probe.output.utf8)) as! [String:Any]
        let stream = (json["streams"] as! [[String:Any]])[0]
        XCTAssertEqual(stream["avg_frame_rate"] as? String,"10/1")
        XCTAssertEqual(stream["nb_frames"] as? String,"3")
        XCTAssertEqual(stream["codec_name"] as? String,"h264")
    }
    func testCacheReuseSourceChangeAndCorruption() async throws {
        let folder = try await fixture()
        let cache = root.appendingPathComponent("cache")
        let original = try WallpaperProject.load(folder:folder)
        let before = try Data(contentsOf:URL(fileURLWithPath:original.videoPath))
        let first = try await VideoConverter.prepare(folder:folder,cacheRoot:cache,ffmpeg:ffmpeg)
        let second = try await VideoConverter.prepare(folder:folder,cacheRoot:cache,ffmpeg:URL(fileURLWithPath:"/missing/ffmpeg"))
        XCTAssertEqual(first,second)
        try Data("corrupt".utf8).write(to:URL(fileURLWithPath:first.videoPath))
        let rebuilt = try await VideoConverter.prepare(folder:folder,cacheRoot:cache,ffmpeg:ffmpeg)
        XCTAssertEqual(rebuilt,first)
        _ = try await MediaValidator.validate(url:URL(fileURLWithPath:rebuilt.videoPath))
        try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:2_000_000_000)],ofItemAtPath:original.videoPath)
        let updated = try await VideoConverter.prepare(folder:folder,cacheRoot:cache,ffmpeg:ffmpeg)
        XCTAssertEqual(updated.id,first.id,"Reimporting an updated source must replace the same library project")
        XCTAssertNotEqual(updated.videoPath,first.videoPath,"Updated media must get a new playback URL")
        XCTAssertEqual(try Data(contentsOf:URL(fileURLWithPath:original.videoPath)),before)
        XCTAssertEqual(try WallpaperProject.load(folder:folder),original)
    }
    func testMissingToolFailureAndCancellationLeaveNoPartialProject() async throws {
        let folder = try await fixture()
        let cache = root.appendingPathComponent("cache")
        do { _ = try await VideoConverter.prepare(folder:folder,cacheRoot:cache,ffmpeg:URL(fileURLWithPath:"/missing/ffmpeg")); XCTFail("Expected missing tool") }
        catch { XCTAssertTrue(error.localizedDescription.contains("FFmpeg")) }
        let failure = try script("echo 'failed to encode'; exit 1\n")
        do { _ = try await VideoConverter.prepare(folder:folder,cacheRoot:cache,ffmpeg:failure); XCTFail("Expected failure") } catch { }
        let sleeper = try script("sleep 20\n")
        let task = Task { try await VideoConverter.prepare(folder:folder,cacheRoot:cache,ffmpeg:sleeper) }
        try await Task.sleep(for:.milliseconds(150)); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let files = (try? FileManager.default.contentsOfDirectory(atPath:cache.path)) ?? []
        XCTAssertTrue(files.isEmpty,"No failed/cancelled conversion may remain")
        XCTAssertNoThrow(try WallpaperProject.load(folder:folder))
    }
    func testInvalidMP4DoesNotChangeLibrary() async throws {
        _ = NSApplication.shared
        let folder = root.appendingPathComponent("invalid")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try Data("{\"type\":\"video\",\"file\":\"bad.mp4\"}".utf8).write(to:folder.appendingPathComponent("project.json"))
        try Data("invalid mp4".utf8).write(to:folder.appendingPathComponent("bad.mp4"))
        let library = LibraryModel(storeURL:root.appendingPathComponent("state.json"))
        defer { library.engine.stop() }
        let before = library.state
        let id = await library.importFolder(folder)
        XCTAssertNil(id); XCTAssertEqual(library.state,before); XCTAssertNotNil(library.errorMessage)
    }
    func testRealWebMWorkshopImportApplyRestoreAndDeduplicate() async throws {
        guard let path = ProcessInfo.processInfo.environment["CONVERSION_WEBM_FOLDER"] else { throw XCTSkip("Set CONVERSION_WEBM_FOLDER") }
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath:path)
        let source = try WallpaperProject.load(folder:folder)
        let original = try Data(contentsOf:URL(fileURLWithPath:source.videoPath))
        let manifest = try Data(contentsOf:folder.appendingPathComponent("project.json"))
        let store = root.appendingPathComponent("state.json")
        let library = LibraryModel(storeURL:store)
        defer { library.engine.stop() }
        let workshop = WorkshopModel(library:library,preferencesURL:root.appendingPathComponent("workshop.json"))
        let result = try await workshop.importVideo(folder)
        XCTAssertEqual(result,.imported)
        let project = try XCTUnwrap(library.state.projects.first)
        XCTAssertEqual(URL(fileURLWithPath:project.videoPath).pathExtension,"mp4")
        XCTAssertEqual(URL(fileURLWithPath:project.folderPath).lastPathComponent,"901037918")
        XCTAssertEqual(try Data(contentsOf:URL(fileURLWithPath:try XCTUnwrap(project.previewPath))),try Data(contentsOf:URL(fileURLWithPath:try XCTUnwrap(source.previewPath))))
        XCTAssertTrue(workshop.alreadyImported(try WorkshopID("901037918")))
        let duplicate = try await workshop.importVideo(folder)
        XCTAssertEqual(duplicate,.existing); XCTAssertEqual(library.state.projects.count,1)
        await library.apply(projectID:project.id,target:nil,fit:.fit)
        XCTAssertNil(library.errorMessage); XCTAssertEqual(library.state.defaultAssignment?.projectID,project.id)
        library.togglePause(); library.engine.stop()
        let restored = LibraryModel(storeURL:store)
        defer { restored.engine.stop() }
        await restored.restore()
        XCTAssertNil(restored.errorMessage); XCTAssertEqual(restored.state,library.state)
        XCTAssertEqual(restored.mediaInfo[project.id]?.width,1920)
        XCTAssertEqual(try Data(contentsOf:URL(fileURLWithPath:source.videoPath)),original)
        XCTAssertEqual(try Data(contentsOf:folder.appendingPathComponent("project.json")),manifest)
    }
    func testWorkshopCancellationDuringConversionPreservesLibrary() async throws {
        guard let path = ProcessInfo.processInfo.environment["CONVERSION_WEBM_FOLDER"] else { throw XCTSkip("Set CONVERSION_WEBM_FOLDER") }
        _ = NSApplication.shared
        let library = LibraryModel(storeURL:root.appendingPathComponent("state.json"))
        defer { library.engine.stop() }
        let workshop = WorkshopModel(library:library,preferencesURL:root.appendingPathComponent("workshop.json"))
        let before = library.state
        let task = Task { try await workshop.importVideo(URL(fileURLWithPath:path)) }
        for _ in 0..<100 where library.importStatus == nil { try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertNotNil(library.importStatus)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(library.state,before)
        XCTAssertNil(library.importStatus)
        XCTAssertFalse(library.isBusy)
        let cache = root.appendingPathComponent("ConvertedVideos")
        XCTAssertTrue(((try? FileManager.default.contentsOfDirectory(atPath:cache.path)) ?? []).isEmpty)
    }
    func testShutdownStopsManualConversionWithoutImporting() async throws {
        guard let path = ProcessInfo.processInfo.environment["CONVERSION_WEBM_FOLDER"] else { throw XCTSkip("Set CONVERSION_WEBM_FOLDER") }
        _ = NSApplication.shared
        let library = LibraryModel(storeURL:root.appendingPathComponent("state.json"))
        defer { library.engine.stop() }
        let before = library.state
        let task = Task { await library.importFolder(URL(fileURLWithPath:path)) }
        for _ in 0..<100 where library.importStatus == nil { try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertNotNil(library.importStatus)
        library.shutdown()
        let id = await task.value
        XCTAssertNil(id); XCTAssertEqual(library.state,before); XCTAssertFalse(library.isBusy)
        let cache = root.appendingPathComponent("ConvertedVideos")
        XCTAssertTrue(((try? FileManager.default.contentsOfDirectory(atPath:cache.path)) ?? []).isEmpty)
    }
    func testSourceUpdatesAndFormatChangesKeepOneProjectAndAssignments() async throws {
        _ = NSApplication.shared
        let folder = try await fixture("mp4")
        let manifest = try Data(contentsOf:folder.appendingPathComponent("project.json"))
        let library = LibraryModel(storeURL:root.appendingPathComponent("state.json"))
        defer { library.engine.stop() }
        let importedNative = await library.importFolder(folder)
        let nativeID = try XCTUnwrap(importedNative)
        await library.apply(projectID:nativeID,target:nil,fit:.fit)
        library.togglePause()
        _ = try await fixture("mov")
        let importedConverted = await library.importFolder(folder)
        let convertedID = try XCTUnwrap(importedConverted)
        XCTAssertEqual(library.state.projects.count,1)
        XCTAssertEqual(library.state.defaultAssignment?.projectID,convertedID)
        XCTAssertEqual(library.state.defaultAssignment?.fit,.fit)
        XCTAssertTrue(library.state.manuallyPaused)
        let oldPath = try XCTUnwrap(library.state.projects.first?.videoPath)
        let source = try WallpaperProject.load(folder:folder)
        try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:2_000_000_000)],ofItemAtPath:source.videoPath)
        let updatedID = await library.importFolder(folder)
        XCTAssertEqual(updatedID,convertedID); XCTAssertEqual(library.state.projects.count,1)
        XCTAssertNotEqual(library.state.projects.first?.videoPath,oldPath)
        await library.apply(projectID:convertedID,target:nil,fit:.fit)
        XCTAssertNil(library.errorMessage)
        XCTAssertEqual(library.engine.sessions.values.first?.videoPath,library.state.projects.first?.videoPath)
        try manifest.write(to:folder.appendingPathComponent("project.json"))
        let backToNative = await library.importFolder(folder)
        XCTAssertEqual(backToNative,nativeID); XCTAssertEqual(library.state.projects.count,1)
        XCTAssertEqual(library.state.defaultAssignment?.projectID,nativeID)
        XCTAssertTrue(library.state.assignments.values.allSatisfy { $0.projectID == nativeID && $0.fit == .fit })
        XCTAssertTrue(library.state.manuallyPaused)
    }
    func testRejectedUpdatedImportKeepsPreviousCachedVideoPlayable() async throws {
        _ = NSApplication.shared
        let folder = try await fixture()
        let store = root.appendingPathComponent("state.json")
        let library = LibraryModel(storeURL:store)
        defer { library.engine.stop() }
        let imported = await library.importFolder(folder)
        let id = try XCTUnwrap(imported)
        await library.apply(projectID:id,target:nil,fit:.fit)
        let before = library.state
        let old = try XCTUnwrap(before.projects.first)
        let source = try WallpaperProject.load(folder:folder)
        try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:2_000_000_000)],ofItemAtPath:source.videoPath)
        let rejected = await library.importFolder(folder) { _ in library.refreshDisplays() }
        XCTAssertNil(rejected); XCTAssertEqual(library.state,before)
        let cached = try WallpaperProject.load(folder:URL(fileURLWithPath:old.folderPath))
        XCTAssertEqual(cached.videoPath,old.videoPath)
        _ = try await MediaValidator.validate(url:URL(fileURLWithPath:old.videoPath))
        let restored = LibraryModel(storeURL:store)
        defer { restored.engine.stop() }
        await restored.restore()
        XCTAssertNil(restored.errorMessage)
        XCTAssertEqual(restored.state,before)
    }
    func testOddDimensionsArePaddedForH264() async throws {
        let folder = try await fixture(size:"65x65")
        let prepared = try await VideoConverter.prepare(folder:folder,cacheRoot:root.appendingPathComponent("cache"),ffmpeg:ffmpeg)
        let info = try await MediaValidator.validate(url:URL(fileURLWithPath:prepared.videoPath))
        XCTAssertEqual(info.width,66); XCTAssertEqual(info.height,66)
        XCTAssertEqual(info.duration,0.3,accuracy:0.05)
    }
    func testConversionPreservesAudioAsAAC() async throws {
        let folder = try await fixture("mov")
        let source = try WallpaperProject.load(folder:folder)
        let audioFile = folder.appendingPathComponent("with-audio.mov")
        let generated = try await SteamRunner.run(executable:ffmpeg,arguments:["-nostdin","-v","error","-i",source.videoPath,"-f","lavfi","-i","sine=frequency=440:sample_rate=48000:duration=0.3","-map","0:v:0","-map","1:a:0","-c:v","copy","-c:a","pcm_s16le","-shortest",audioFile.path])
        XCTAssertEqual(generated.exitCode,0,generated.output)
        try Data("{\"type\":\"video\",\"file\":\"with-audio.mov\"}".utf8).write(to:folder.appendingPathComponent("project.json"))
        let prepared = try await VideoConverter.prepare(folder:folder,cacheRoot:root.appendingPathComponent("cache"),ffmpeg:ffmpeg)
        let tracks = try await AVURLAsset(url:URL(fileURLWithPath:prepared.videoPath)).loadTracks(withMediaType:.audio)
        XCTAssertEqual(tracks.count,1,"The mute switch must be able to restore sound after conversion")
        let result = try await SteamRunner.run(executable:ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe"),arguments:["-v","error","-select_streams","a:0","-show_entries","stream=codec_name","-of","default=nw=1:nk=1",prepared.videoPath])
        XCTAssertEqual(result.exitCode,0)
        XCTAssertEqual(result.output.trimmingCharacters(in:.whitespacesAndNewlines),"aac")
    }
}
