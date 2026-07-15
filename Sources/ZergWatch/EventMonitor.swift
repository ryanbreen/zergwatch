import AppKit
import CoreGraphics
import Foundation

final class EventMonitor {
    private weak var store: APMStore?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyboardHIDMonitor: KeyboardHIDMonitor?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    init(store: APMStore) {
        self.store = store
    }

    deinit {
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        stopKeyboardCapture()
    }

    @MainActor
    func start() -> Bool {
        guard eventTap == nil else {
            let keyboardActive = installKeyboardCaptureIfNeeded()
            store?.setEventTapActive(keyboardActive)
            return keyboardActive
        }

        // Keyboard events are captured separately via IOHIDManager, which can read
        // keyboard HID values directly even when Karabiner-Elements owns the device.
        // The CGEventTap remains mouse-only so keyboard paths cannot double count.
        let eventMask = Self.mask(for: [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .tapDisabledByTimeout,
            .tapDisabledByUserInput
        ])

        // Tap at the session level first: Karabiner-Elements SEIZES the keyboard
        // HID device, so an HID-level tap sees zero keyboard events (only mouse)
        // when Karabiner is running. The session tap sees keyboard combos because
        // Karabiner re-emits synthesized events at the session level. Fall back to
        // the HID level if a session-level tap can't be created.
        var createdTap: CFMachPort?
        for location in [CGEventTapLocation.cgSessionEventTap, .cghidEventTap] {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: eventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) {
                createdTap = tap
                break
            }
        }
        guard let tap = createdTap else {
            store?.setEventTapActive(false)
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            store?.setEventTapActive(false)
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let keyboardActive = installKeyboardCaptureIfNeeded()
        store?.setEventTapActive(keyboardActive)
        return keyboardActive
    }

    @MainActor
    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        stopKeyboardCapture()
        runLoopSource = nil
        eventTap = nil
        store?.setEventTapActive(false)
    }

    @MainActor
    private func installKeyboardCaptureIfNeeded() -> Bool {
        if keyboardHIDMonitor != nil || globalKeyMonitor != nil || localKeyMonitor != nil {
            return true
        }

        if let store {
            let hidMonitor = KeyboardHIDMonitor(store: store)
            if hidMonitor.start() {
                keyboardHIDMonitor = hidMonitor
                return true
            }
        }

        installKeyboardMonitors()
        return globalKeyMonitor != nil || localKeyMonitor != nil
    }

    private func stopKeyboardCapture() {
        keyboardHIDMonitor?.stop()
        keyboardHIDMonitor = nil
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        globalKeyMonitor = nil
        localKeyMonitor = nil
    }

    @MainActor
    private func installKeyboardMonitors() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
    }

    @MainActor
    private func handleKeyDown(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifierMask = Self.modifierMask(from: mods)
        store?.record(.keyDown(keyCode: keyCode, modifierMask: modifierMask))
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        let capturedEvent: CapturedInputEvent?
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            capturedEvent = .mouseDown
        default:
            capturedEvent = nil
        }

        guard let capturedEvent else {
            return
        }

        let store = store
        Task { @MainActor in
            store?.record(capturedEvent)
        }
    }

    private static func mask(for eventTypes: [CGEventType]) -> CGEventMask {
        eventTypes.reduce(CGEventMask(0)) { partialResult, eventType in
            partialResult | (CGEventMask(1) << eventType.rawValue)
        }
    }

    private static func modifierMask(from mods: NSEvent.ModifierFlags) -> Int {
        var mask = 0
        if mods.contains(.command) {
            mask |= ModifierMask.command
        }
        if mods.contains(.option) {
            mask |= ModifierMask.option
        }
        if mods.contains(.control) {
            mask |= ModifierMask.control
        }
        if mods.contains(.shift) {
            mask |= ModifierMask.shift
        }
        return mask
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<EventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.handle(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
