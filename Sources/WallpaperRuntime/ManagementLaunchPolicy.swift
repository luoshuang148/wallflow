import AppKit
import Carbon

public enum ManagementLaunchPolicy {
    public static func startsInBackground(_ event: NSAppleEventDescriptor?) -> Bool {
        event?.eventClass == AEEventClass(kCoreEventClass) && event?.eventID == AEEventID(kAEOpenApplication) &&
        event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
