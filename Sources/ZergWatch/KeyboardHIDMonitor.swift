import Foundation
import IOKit
import IOKit.hid

final class KeyboardHIDMonitor {
    private weak var store: APMStore?
    private var manager: IOHIDManager?
    private var heldModifierUsages = Set<UInt32>()
    private var isScheduled = false

    init(store: APMStore) {
        self.store = store
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        guard manager == nil else {
            return true
        }

        let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let keyboardMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: 0x01,
            kIOHIDDeviceUsageKey: 0x06
        ]

        IOHIDManagerSetDeviceMatching(hidManager, keyboardMatch as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(
            hidManager,
            keyboardHIDValueCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(
            hidManager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        isScheduled = true

        let openResult = IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(
                hidManager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            IOHIDManagerRegisterInputValueCallback(hidManager, nil, nil)
            isScheduled = false
            return false
        }

        manager = hidManager
        return true
    }

    func stop() {
        guard let manager else {
            heldModifierUsages.removeAll(keepingCapacity: true)
            return
        }

        if isScheduled {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        self.manager = nil
        isScheduled = false
        heldModifierUsages.removeAll(keepingCapacity: true)
    }

    fileprivate func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        guard usagePage == Self.keyboardUsagePage else {
            return
        }

        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        if Self.isModifierUsage(usage) {
            if intValue == 0 {
                heldModifierUsages.remove(usage)
            } else {
                heldModifierUsages.insert(usage)
            }
            return
        }

        guard intValue == 1 else {
            return
        }

        let modifierMask = Self.modifierMask(from: heldModifierUsages)
        let keyCode = Self.macKeyCode(forHIDUsage: usage)
        let store = store
        Task { @MainActor in
            store?.record(.keyDown(keyCode: keyCode ?? -1, modifierMask: modifierMask))
        }
    }

    private static let keyboardUsagePage: UInt32 = 0x07

    private static func isModifierUsage(_ usage: UInt32) -> Bool {
        (0xE0...0xE7).contains(usage)
    }

    private static func modifierMask(from usages: Set<UInt32>) -> Int {
        var mask = 0
        if usages.contains(0xE3) || usages.contains(0xE7) {
            mask |= ModifierMask.command
        }
        if usages.contains(0xE2) || usages.contains(0xE6) {
            mask |= ModifierMask.option
        }
        if usages.contains(0xE0) || usages.contains(0xE4) {
            mask |= ModifierMask.control
        }
        if usages.contains(0xE1) || usages.contains(0xE5) {
            mask |= ModifierMask.shift
        }
        return mask
    }

    private static func macKeyCode(forHIDUsage usage: UInt32) -> Int? {
        hidUsageToMacKeyCode[usage]
    }

    private static let hidUsageToMacKeyCode: [UInt32: Int] = [
        0x04: 0,    // A
        0x05: 11,   // B
        0x06: 8,    // C
        0x07: 2,    // D
        0x08: 14,   // E
        0x09: 3,    // F
        0x0A: 5,    // G
        0x0B: 4,    // H
        0x0C: 34,   // I
        0x0D: 38,   // J
        0x0E: 40,   // K
        0x0F: 37,   // L
        0x10: 46,   // M
        0x11: 45,   // N
        0x12: 31,   // O
        0x13: 35,   // P
        0x14: 12,   // Q
        0x15: 15,   // R
        0x16: 1,    // S
        0x17: 17,   // T
        0x18: 32,   // U
        0x19: 9,    // V
        0x1A: 13,   // W
        0x1B: 7,    // X
        0x1C: 16,   // Y
        0x1D: 6,    // Z
        0x1E: 18,   // 1
        0x1F: 19,   // 2
        0x20: 20,   // 3
        0x21: 21,   // 4
        0x22: 23,   // 5
        0x23: 22,   // 6
        0x24: 26,   // 7
        0x25: 28,   // 8
        0x26: 25,   // 9
        0x27: 29,   // 0
        0x28: 36,   // Return
        0x29: 53,   // Escape
        0x2A: 51,   // Delete
        0x2B: 48,   // Tab
        0x2C: 49,   // Space
        0x2D: 27,   // -
        0x2E: 24,   // =
        0x2F: 33,   // [
        0x30: 30,   // ]
        0x31: 42,   // Backslash
        0x32: 10,   // Non-US # / ISO section
        0x33: 41,   // ;
        0x34: 39,   // '
        0x35: 50,   // `
        0x36: 43,   // ,
        0x37: 47,   // .
        0x38: 44,   // /
        0x39: 57,   // Caps Lock
        0x3A: 122,  // F1
        0x3B: 120,  // F2
        0x3C: 99,   // F3
        0x3D: 118,  // F4
        0x3E: 96,   // F5
        0x3F: 97,   // F6
        0x40: 98,   // F7
        0x41: 100,  // F8
        0x42: 101,  // F9
        0x43: 109,  // F10
        0x44: 103,  // F11
        0x45: 111,  // F12
        0x49: 114,  // Insert / Help
        0x4A: 115,  // Home
        0x4B: 116,  // Page Up
        0x4C: 117,  // Forward Delete
        0x4D: 119,  // End
        0x4E: 121,  // Page Down
        0x4F: 124,  // Right Arrow
        0x50: 123,  // Left Arrow
        0x51: 125,  // Down Arrow
        0x52: 126,  // Up Arrow
        0x53: 71,   // Keypad Clear / Num Lock
        0x54: 75,   // Keypad /
        0x55: 67,   // Keypad *
        0x56: 78,   // Keypad -
        0x57: 69,   // Keypad +
        0x58: 76,   // Keypad Enter
        0x59: 83,   // Keypad 1
        0x5A: 84,   // Keypad 2
        0x5B: 85,   // Keypad 3
        0x5C: 86,   // Keypad 4
        0x5D: 87,   // Keypad 5
        0x5E: 88,   // Keypad 6
        0x5F: 89,   // Keypad 7
        0x60: 91,   // Keypad 8
        0x61: 92,   // Keypad 9
        0x62: 82,   // Keypad 0
        0x63: 65,   // Keypad .
        0x64: 10,   // Non-US backslash / ISO section
        0x67: 81,   // Keypad =
        0x68: 105,  // F13
        0x69: 107,  // F14
        0x6A: 113,  // F15
        0x6B: 106,  // F16
        0x6C: 64,   // F17
        0x6D: 79,   // F18
        0x6E: 80,   // F19
        0x6F: 90,   // F20
        0x85: 95,   // Keypad ,
        0x87: 93,   // JIS Yen
        0x89: 94    // JIS Underscore
    ]

}

private let keyboardHIDValueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else {
        return
    }

    let monitor = Unmanaged<KeyboardHIDMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.handle(value: value)
}
