import Foundation
import IOKit.ps

/// Delivers power changes on the main run loop, without polling or special permissions.
@MainActor public final class PowerMonitor {
    private var source: CFRunLoopSource?
    private var observer: NSObjectProtocol?
    private let onChange: (Bool, Bool) -> Void
    private var lastValue: [Bool]?

    public init(onChange: @escaping (Bool, Bool) -> Void) { self.onChange = onChange }
    public func start() {
        stop()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
            }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }
    public func refresh() {
        var onBattery = false
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() {
            onBattery = (type as String) == kIOPSBatteryPowerValue
        }
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard lastValue != [onBattery, lowPowerMode] else { return }
        lastValue = [onBattery, lowPowerMode]
        onChange(onBattery, lowPowerMode)
    }
    public func stop() {
        if let source { CFRunLoopSourceInvalidate(source) }
        source = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        lastValue = nil
    }
    deinit {
        if let source { CFRunLoopSourceInvalidate(source) }
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
