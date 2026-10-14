import AppKit

@MainActor public enum ManagementWindowPolicy {
    public static func allowQuitWithPresentedSheet(in window: NSWindow) {
        // Management edits are persisted immediately and pending imports are cancelled
        // by the delegate. These sheets do not need to prevent application termination.
        window.attachedSheet?.preventsApplicationTerminationWhenModal = false
    }
}
