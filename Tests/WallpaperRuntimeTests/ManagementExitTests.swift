import XCTest
import AppKit
@testable import WallpaperRuntime

@MainActor final class ManagementExitTests: XCTestCase {
    func testManagementSheetAllowsVerifiedCompleteExitAndCommandQ() {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false; sheet.isReleasedWhenClosed = false
        defer { parent.endSheet(sheet); sheet.orderOut(nil); parent.orderOut(nil) }
        parent.beginSheet(sheet)
        XCTAssertTrue(sheet.preventsApplicationTerminationWhenModal)
        ManagementWindowPolicy.allowQuitWithPresentedSheet(in: parent)
        XCTAssertFalse(sheet.preventsApplicationTerminationWhenModal)
        XCTAssertTrue(parent.preventsApplicationTerminationWhenModal)
    }
    func testCompleteExitQuiescesBeforeStopAndTerminatesOnlyAfterSuccess() async {
        var events: [String] = []
        let exit = ManagementExitCoordinator(quiesce: { events.append("quiesce") }, stop: { _ in events.append("stop") },
            recover: { events.append("recover") }, terminate: { events.append("terminate") })
        await exit.stopWallpaperAndExit()
        XCTAssertEqual(events, ["quiesce", "stop", "terminate"])
        XCTAssertNil(exit.errorMessage)
    }
    func testFailedCompleteExitKeepsManagerAvailableForRetry() async {
        var events: [String] = [], fails = true
        let exit = ManagementExitCoordinator(quiesce: { events.append("quiesce") }, stop: { _ in
            events.append("stop")
            if fails { throw NSError(domain: "playerStillRunning", code: 1) }
        }, recover: { events.append("recover") }, terminate: { events.append("terminate") })
        await exit.stopWallpaperAndExit()
        XCTAssertEqual(events, ["quiesce", "stop", "recover"])
        XCTAssertNotNil(exit.errorMessage)
        XCTAssertFalse(exit.isExiting)
        fails = false
        await exit.stopWallpaperAndExit()
        XCTAssertEqual(events.suffix(3), ["quiesce", "stop", "terminate"])
    }
    func testActualStoppedNotificationHandlerChecksSessionAndUsesExitGate() async {
        let old = UUID()
        var expected: UUID?, terminated = false
        let exit = ManagementExitCoordinator(quiesce: {}, stop: { session in
            expected = session
            throw NSError(domain: "newHelperStarted", code: 1)
        }, recover: {}, terminate: { terminated = true })
        await exit.playerStopped(session: UUID(), connectedSession: old)
        XCTAssertNil(expected)
        await exit.playerStopped(session: old, connectedSession: old)
        XCTAssertEqual(expected, old)
        XCTAssertFalse(terminated)
        XCTAssertNotNil(exit.errorMessage)
    }
}
