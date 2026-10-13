import XCTest
import AppKit
import ServiceManagement
@testable import WallpaperRuntime

@MainActor private final class SimulatedLoginService: LoginStartupService {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var registrationError: Error?
    var unregistrationError: Error?
    var registrations = 0
    var unregistrations = 0
    var settingsOpened = false

    func register() throws {
        registrations += 1
        if let registrationError { throw registrationError }
        status = registrationStatus
    }
    func unregister() throws {
        unregistrations += 1
        if let unregistrationError { throw unregistrationError }
        status = .notRegistered
    }
    func openSettings() { settingsOpened = true }
}

final class SystemIntegrationTests: XCTestCase {
    @MainActor func testStartupReadsSystemStatusAndRefreshesExternalChanges() {
        let service = SimulatedLoginService()
        service.status = .enabled
        let model = LoginStartupModel(service: service)
        XCTAssertTrue(model.enabled)
        XCTAssertFalse(model.needsApproval)
        service.status = .requiresApproval
        model.refresh()
        XCTAssertFalse(model.enabled)
        XCTAssertTrue(model.needsApproval)
        service.status = .notRegistered
        model.refresh()
        XCTAssertFalse(model.enabled)
        XCTAssertFalse(model.needsApproval)
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(service.unregistrations, 0)
    }

    @MainActor func testStartupEnableUsesResultingSystemStatusInsteadOfRequestedValue() {
        let service = SimulatedLoginService()
        service.registrationStatus = .requiresApproval
        let model = LoginStartupModel(service: service)
        model.setEnabled(true)
        XCTAssertFalse(model.enabled)
        XCTAssertTrue(model.needsApproval)
        XCTAssertNil(model.errorMessage)
        model.setEnabled(true)
        XCTAssertEqual(service.registrations, 1, "Pending approval is already registered; retrying causes an OS error")
        model.openSettings()
        XCTAssertTrue(service.settingsOpened)
    }

    @MainActor func testStartupRegistrationFailureRetainsActualStatusAndSurfacesError() {
        let service = SimulatedLoginService()
        service.registrationError = NSError(domain: "LoginTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Registration denied"])
        let model = LoginStartupModel(service: service)
        model.setEnabled(true)
        XCTAssertFalse(model.enabled)
        XCTAssertFalse(model.needsApproval)
        XCTAssertTrue(model.errorMessage?.contains("Registration denied") == true)
        service.registrationError = nil
        model.setEnabled(true)
        XCTAssertTrue(model.enabled)
        XCTAssertNil(model.errorMessage)
        model.setEnabled(true)
        XCTAssertEqual(service.registrations, 2, "Enabling an enabled item must be a no-op")
    }

    @MainActor func testStartupDisableUnregistersBothEnabledAndPendingApproval() {
        for status: SMAppService.Status in [.enabled, .requiresApproval] {
            let service = SimulatedLoginService()
            service.status = status
            let model = LoginStartupModel(service: service)
            model.setEnabled(false)
            XCTAssertFalse(model.enabled)
            XCTAssertFalse(model.needsApproval)
            XCTAssertEqual(service.unregistrations, 1)
            model.setEnabled(false)
            XCTAssertEqual(service.unregistrations, 1)
        }
    }

    @MainActor func testStartupUnregistrationFailureDoesNotClaimDisabled() {
        let service = SimulatedLoginService()
        service.status = .enabled
        service.unregistrationError = NSError(domain: "LoginTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Removal failed"])
        let model = LoginStartupModel(service: service)
        model.setEnabled(false)
        XCTAssertTrue(model.enabled)
        XCTAssertTrue(model.errorMessage?.contains("Removal failed") == true)
    }

    @MainActor func testStartupNotFoundReportsAnActionableError() {
        let service = SimulatedLoginService()
        service.status = .notFound
        let model = LoginStartupModel(service: service)
        XCTAssertFalse(model.enabled)
        XCTAssertFalse(model.needsApproval)
        XCTAssertNotNil(model.errorMessage)
        service.status = .enabled
        model.refresh()
        XCTAssertTrue(model.enabled)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor func testApplicationMonitorPublishesInitialSnapshotAndSuppressesUnchangedValues() {
        let center = NotificationCenter()
        var running: Set<String> = ["com.example.editor"]
        var frontmost: String? = "com.example.editor"
        var snapshots: [(Set<String>, String?)] = []
        let monitor = ApplicationMonitor(notificationCenter: center, runningBundleIDs: { running }, frontmostBundleID: { frontmost }) {
            snapshots.append(($0, $1))
        }
        monitor.start()
        monitor.refresh()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.0, ["com.example.editor"])
        XCTAssertEqual(snapshots.first?.1, "com.example.editor")
        running.insert("com.example.game")
        frontmost = nil
        monitor.refresh()
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.last?.0, ["com.example.editor", "com.example.game"])
        XCTAssertNil(snapshots.last?.1)
        monitor.stop()
    }

    @MainActor func testApplicationMonitorRespondsToWorkspaceEventsAndStopsObserving() async {
        let center = NotificationCenter()
        var running: Set<String> = []
        var frontmost: String?
        var snapshots: [(Set<String>, String?)] = []
        let monitor = ApplicationMonitor(notificationCenter: center, runningBundleIDs: { running }, frontmostBundleID: { frontmost }) {
            snapshots.append(($0, $1))
        }
        monitor.start()
        running = ["com.example.game"]
        center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(snapshots.last?.0, ["com.example.game"])
        frontmost = "com.example.game"
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(snapshots.last?.1, "com.example.game")
        running = []
        frontmost = nil
        center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(snapshots.last?.0, [])
        XCTAssertNil(snapshots.last?.1)
        monitor.stop()
        let countAfterStop = snapshots.count
        running = ["com.example.other"]
        center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(snapshots.count, countAfterStop)
        monitor.start()
        XCTAssertEqual(snapshots.count, countAfterStop + 1)
        XCTAssertEqual(snapshots.last?.0, ["com.example.other"])
        monitor.stop()
    }
}
