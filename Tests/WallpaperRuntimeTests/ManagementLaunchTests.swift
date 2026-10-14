import XCTest
import AppKit
import Carbon
@testable import WallpaperRuntime

final class ManagementLaunchTests: XCTestCase {
    func testLoginOpenEventStartsWithoutManagementUI() {
        let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        XCTAssertTrue(ManagementLaunchPolicy.startsInBackground(event))
    }
    func testManualOpenAndReopenNeverHideManagement() {
        XCTAssertFalse(ManagementLaunchPolicy.startsInBackground(nil))
        for id in [kAEOpenApplication, kAEReopenApplication] {
            let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(id),
                targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            if id == kAEReopenApplication {
                event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
            }
            XCTAssertFalse(ManagementLaunchPolicy.startsInBackground(event))
        }
    }
}
