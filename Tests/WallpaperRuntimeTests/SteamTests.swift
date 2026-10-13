import XCTest
import AppKit
import Darwin
@testable import WallpaperCore
@testable import WallpaperRuntime

final class SteamTests: XCTestCase {
    @MainActor func testLocalScanImportsCapitalizedVideoType() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLPAPER_SAMPLE"] else { throw XCTSkip("Set WALLPAPER_SAMPLE") }
        _ = NSApplication.shared
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appendingPathComponent("content/431960")
        let folder = root.appendingPathComponent("12345")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: URL(fileURLWithPath: path), to: folder.appendingPathComponent("video.mp4"))
        try Data("{\"type\":\"Video\",\"file\":\"video.mp4\",\"title\":\"Capitalized video\"}".utf8).write(to: folder.appendingPathComponent("project.json"))
        let library = LibraryModel(storeURL: temp.appendingPathComponent("state.json"))
        defer { library.engine.stop() }
        let workshop = WorkshopModel(library: library, preferencesURL: temp.appendingPathComponent("workshop.json"))
        workshop.scanLocal(root)
        while workshop.isBusy { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(library.state.projects.map(\.title), ["Capitalized video"])
        XCTAssertTrue(workshop.failures.isEmpty)
        XCTAssertNil(library.state.defaultAssignment)
    }
    func testRunnerDrainsLargeOutputAndKeepsTail() async throws {
        let result = try await SteamRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "i=0; while [ $i -lt 5000 ]; do printf 'abcdefghijklmnopqrstuvwxyz0123456789\\n'; i=$((i+1)); done; echo END"], timeout: 10, outputLimit: 4096)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertLessThanOrEqual(result.output.utf8.count, 4096)
        XCTAssertTrue(result.output.hasSuffix("END\n"))
    }
    func testTimeoutAndCancellationStopActualProcess() async throws {
        let started = Date()
        do {
            _ = try await SteamRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"], timeout: 0.2)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
        let task = Task { try await SteamRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"], timeout: 30) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testPathsRejectUntrustedReportedFolderAndAccountCommands() throws {
        let root = URL(fileURLWithPath: "/tmp/steam/steamapps/workshop/content/431960")
        let id = try WorkshopID("12")
        XCTAssertNoThrow(try SteamPaths.validateDownloadFolder(root.appendingPathComponent("12"), id: id, roots: [root]))
        XCTAssertThrowsError(try SteamPaths.validateDownloadFolder(URL(fileURLWithPath: "/tmp/evil/12"), id: id, roots: [root]))
        XCTAssertThrowsError(try SteamPaths.validateDownloadFolder(root.appendingPathComponent("34"), id: id, roots: [root]))
        for name in ["abc_123", "foo.bar"] { XCTAssertNoThrow(try SteamPaths.validateAccount(name)) }
        for name in ["", "+quit", "foo;touch /tmp/x", "a b", "$(pwd)"] { XCTAssertThrowsError(try SteamPaths.validateAccount(name)) }
    }
    @MainActor func testImportDuplicateIDPreservesAssignmentsAndPause() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else { throw XCTSkip("Set WALLPAPER_FOLDER") }
        _ = NSApplication.shared
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let library = LibraryModel(storeURL: temp.appendingPathComponent("state.json"))
        defer { library.engine.stop() }
        let folder = URL(fileURLWithPath: path)
        _ = await library.importFolder(folder)
        library.togglePause()
        let before = library.state
        let workshop = WorkshopModel(library: library, preferencesURL: temp.appendingPathComponent("workshop.json"))
        let status = try await workshop.importVideo(folder)
        XCTAssertEqual(status, .existing)
        XCTAssertEqual(library.state, before)
        let bad = temp.appendingPathComponent("bad")
        do { _ = try await workshop.importVideo(bad); XCTFail("Expected missing file") } catch { }
        XCTAssertEqual(library.state, before)
    }
    @MainActor func testRealSteamDownloadAndImport() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let toolPath = env["STEAM_TEST_TOOL"], let accountFile = env["STEAM_TEST_ACCOUNT_FILE"] else { throw XCTSkip("Optional authenticated download") }
        _ = NSApplication.shared
        let account = try String(contentsOfFile: accountFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        try SteamPaths.validateAccount(account)
        let tool = URL(fileURLWithPath: toolPath)
        let id = try WorkshopID("3524676173")
        let items = try await WorkshopModel.fetchItems([id])
        XCTAssertTrue(items[0].isVideo)
        let result = try await SteamRunner.run(executable: tool, arguments: ["+@NoPromptForPassword", "1", "+login", account, "+workshop_download_item", "431960", id.rawValue, "+quit"], environment: SteamPaths.environment(tool: tool), timeout: 180)
        let folder = try SteamDownloadResult.folder(output: result.output, exitCode: result.exitCode, id: id)
        try SteamPaths.validateDownloadFolder(folder, id: id, roots: SteamPaths.contentRoots(tool: tool))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let library = LibraryModel(storeURL: temp.appendingPathComponent("state.json"))
        defer { library.engine.stop() }
        let workshop = WorkshopModel(library: library, preferencesURL: temp.appendingPathComponent("workshop.json"))
        let imported = try await workshop.importVideo(folder)
        XCTAssertEqual(imported, .imported)
        XCTAssertEqual(library.state.projects.count, 1)
        XCTAssertNil(library.state.defaultAssignment)
        XCTAssertEqual(library.state.projects.first?.folderPath, folder.path)
    }

    func testDownloadFolderCannotEscapeRootThroughSymlink() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appendingPathComponent("content/431960")
        let outside = temp.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let folder = root.appendingPathComponent("12")
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: outside)
        XCTAssertThrowsError(try SteamPaths.validateDownloadFolder(folder, id: WorkshopID("12"), roots: [root]))
    }

    func testTimeoutStopsChildHoldingOutputPipe() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let childFile = temp.appendingPathComponent("child.pid")
        let started = Date()
        do {
            _ = try await SteamRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "/bin/sh -c 'trap \"\" HUP TERM; sleep 6' & echo $! > " + SteamPaths.shellQuote(childFile.path) + "; wait"], timeout: 0.2)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
        let childPID = try XCTUnwrap(Int32(String(contentsOf: childFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        for _ in 0..<50 {
            if Darwin.kill(childPID, 0) == -1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(Darwin.kill(childPID, 0), -1, "Owned helper must have terminated")
    }
    @MainActor func testWorkshopImportWaitsForStartupRestore() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLPAPER_SAMPLE"] else { throw XCTSkip("Set WALLPAPER_SAMPLE") }
        _ = NSApplication.shared
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        var folders: [URL] = []
        for number in 10000...10005 {
            let folder = temp.appendingPathComponent(String(number))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.linkItem(at: URL(fileURLWithPath: path), to: folder.appendingPathComponent("video.mp4"))
            try Data("{\"type\":\"video\",\"file\":\"video.mp4\",\"title\":\"sample\"}".utf8).write(to: folder.appendingPathComponent("project.json"))
            folders.append(folder)
        }
        let store = temp.appendingPathComponent("state.json")
        var initial = AppState()
        initial.projects = try folders.prefix(5).map { try WallpaperProject.load(folder: $0) }
        initial.defaultAssignment = Assignment(projectID: initial.projects[0].id, fit: .fill)
        initial.manuallyPaused = true
        try StateStore.save(initial, to: store)
        let library = LibraryModel(storeURL: store)
        defer { library.engine.stop() }
        let workshop = WorkshopModel(library: library, preferencesURL: temp.appendingPathComponent("workshop.json"))
        let restoring = Task { await library.restore() }
        while !library.isBusy { await Task.yield() }
        _ = try await workshop.importVideo(folders[5])
        await restoring.value
        XCTAssertEqual(library.mediaInfo.count, 6)
        XCTAssertEqual(library.state.defaultAssignment, initial.defaultAssignment)
        for _ in 0..<50 where library.engine.sessions.isEmpty { try await Task.sleep(for: .milliseconds(40)) }
        XCTAssertEqual(library.engine.sessions.values.first?.projectID, initial.projects[0].id)
    }

}
