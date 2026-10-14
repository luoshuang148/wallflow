import XCTest
import Foundation
import Darwin
@testable import WallpaperRuntime

@MainActor final class BackgroundPlayerTests: XCTestCase {
    private func paths() throws -> BackgroundPlayerPaths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return BackgroundPlayerPaths(stateURL: root.appendingPathComponent("state.json"))
    }
    private func status(_ paths: BackgroundPlayerPaths, session: UUID? = nil, build: String = "test", phase: PlayerPhase = .ready) throws -> PlayerStatus {
        let owner = try paths.readOwnership()
        let value = PlayerStatus(sessionID: session ?? owner?.sessionID ?? UUID(), pid: getpid(), build: build, parentAppPath: "/tmp/WallFlow.app", phase: phase, displays: [:], error: nil)
        try paths.writeStatus(value)
        return value
    }
    func testLeaseExcludesDuplicatesAndReleasesWithoutStalePIDTrust() throws {
        let paths = try paths()
        var first = try XCTUnwrap(PlayerLease.acquire(paths))
        XCTAssertNil(try PlayerLease.acquire(paths))
        _ = try status(paths)
        XCTAssertTrue(try paths.hasOwner())
        first.release()
        XCTAssertFalse(try paths.hasOwner())
        first = try XCTUnwrap(PlayerLease.acquire(paths))
        first.release()
    }
    func testOldQuitCommandDoesNotStopNewSession() throws {
        let paths = try paths(), previous = UUID(), current = UUID()
        try paths.requestStop(session: previous)
        XCTAssertFalse(try paths.stopRequested(session: current))
        XCTAssertTrue(try paths.stopRequested(session: previous))
        try paths.requestStop(session: current)
        XCTAssertTrue(try paths.stopRequested(session: current))
    }
    func testFreshStatusFromAnotherSessionCannotPretendToOwnLease() async throws {
        let paths = try paths(), lease = try XCTUnwrap(PlayerLease.acquire(paths))
        defer { lease.release() }
        _ = try status(paths, session: UUID())
        let controller = BackgroundPlayerController(paths: paths, build: "test", timeout: 0.12) { XCTFail("Already owned") }
        do { try await controller.ensureRunning(); XCTFail("Old status must match the actual lease session") }
        catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
    }
    func testStaleReadyStatusRequiresNewLaunchAndTimeoutIsFailure() async throws {
        let paths = try paths(); _ = try status(paths)
        var launches = 0
        let controller = BackgroundPlayerController(paths: paths, build: "test", timeout: 0.12) { launches += 1 }
        do { try await controller.ensureRunning(); XCTFail("A dead player's status cannot satisfy readiness") }
        catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        XCTAssertEqual(launches, 1)
        XCTAssertNil(controller.status)
    }
    func testExistingHelperIsReusedAndIncompatibleBuildIsRejected() async throws {
        let paths = try paths(), lease = try XCTUnwrap(PlayerLease.acquire(paths))
        defer { lease.release() }
        let current = try status(paths)
        var launches = 0
        let controller = BackgroundPlayerController(paths: paths, build: "test", timeout: 0.12) { launches += 1 }
        try await controller.ensureRunning()
        XCTAssertEqual(controller.status?.sessionID, current.sessionID)
        XCTAssertEqual(launches, 0)
        _ = try status(paths, build: "old")
        do { try await controller.ensureRunning(); XCTFail("Version mismatch must be visible") }
        catch { XCTAssertTrue(error.localizedDescription.contains("完全退出")) }
    }
    func testLaunchErrorAndUnresponsiveQuitAreNotReportedAsSuccess() async throws {
        let paths = try paths()
        let controller = BackgroundPlayerController(paths: paths, build: "test", timeout: 0.12) { throw NSError(domain: "launch", code: 1) }
        do { try await controller.ensureRunning(); XCTFail() } catch { }
        let lease = try XCTUnwrap(PlayerLease.acquire(paths)); defer { lease.release() }
        let current = try status(paths)
        do { try await controller.stopAndWait(); XCTFail("Held lease is still running") }
        catch { XCTAssertTrue(error.localizedDescription.contains("仍在运行")) }
        XCTAssertTrue(try paths.stopRequested(session: current.sessionID))
    }
    func testCompleteExitWaitsForLeaseRelease() async throws {
        let paths = try paths(), lease = try XCTUnwrap(PlayerLease.acquire(paths))
        _ = try status(paths)
        let controller = BackgroundPlayerController(paths: paths, build: "test", timeout: 1, isProcessRunning: { _ in false }) { }
        let release = Task { @MainActor in
            while !(try paths.stopRequested(session: paths.readStatus()!.sessionID)) { try await Task.sleep(for: .milliseconds(10)) }
            lease.release()
        }
        try await controller.stopAndWait()
        try await release.value
        XCTAssertFalse(try paths.hasOwner())
    }
    func testLeaseReleaseAloneIsNotCompleteWhilePlayerProcessStillLives() async throws {
        let paths = try paths(), lease = try XCTUnwrap(PlayerLease.acquire(paths))
        let current = try status(paths)
        let controller = BackgroundPlayerController(paths: paths, build: "test", timeout: 0.2) { }
        let release = Task { @MainActor in
            while !(try paths.stopRequested(session: current.sessionID)) { try await Task.sleep(for: .milliseconds(10)) }
            lease.release()
        }
        do { try await controller.stopAndWait(); XCTFail("Process must also exit") }
        catch { XCTAssertTrue(error.localizedDescription.contains("仍在运行")) }
        try await release.value
    }
}
