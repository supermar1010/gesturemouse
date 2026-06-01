// debug-buttons.swift
//
// Standalone helper to identify mouse button indices. Prints button number +
// event type for every "other" (non-left/right/middle) mouse event. Does not
// swallow events.
//
// Build:
//   swiftc debug-buttons.swift -O \
//     -framework CoreGraphics -framework ApplicationServices \
//     -o debug-buttons
//
// Run:
//   ./debug-buttons
//
// Press every button on the mouse. Note the index printed for the thumb
// gesture button — put that number into ~/.config/gesturemouse/config.json
// as the "button" field.

import Foundation
import CoreGraphics
import ApplicationServices

func ensureAccessibility() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let opts = [key: true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(opts) {
        FileHandle.standardError.write(Data("debug-buttons: grant Accessibility, then re-run\n".utf8))
        exit(2)
    }
}

ensureAccessibility()

var sharedTap: CFMachPort? = nil

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async {
            if let t = sharedTap { CGEvent.tapEnable(tap: t, enable: true) }
        }
        return Unmanaged.passUnretained(event)
    }

    let btn = event.getIntegerValueField(.mouseEventButtonNumber)
    let pos = event.location
    let kind: String
    switch type {
    case .leftMouseDown:   kind = "leftDown"
    case .leftMouseUp:     kind = "leftUp"
    case .rightMouseDown:  kind = "rightDown"
    case .rightMouseUp:    kind = "rightUp"
    case .otherMouseDown:  kind = "otherDown"
    case .otherMouseUp:    kind = "otherUp"
    case .scrollWheel:
        let d1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let d2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let cont = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        print("scroll  axis1=\(d1) axis2=\(d2) continuous=\(cont)")
        return Unmanaged.passUnretained(event)
    default:
        kind = "type=\(type.rawValue)"
    }
    print("\(kind)  button=\(btn)  pos=(\(Int(pos.x)),\(Int(pos.y)))")
    return Unmanaged.passUnretained(event)
}

let mask: CGEventMask =
    (1 << CGEventType.leftMouseDown.rawValue)  |
    (1 << CGEventType.leftMouseUp.rawValue)    |
    (1 << CGEventType.rightMouseDown.rawValue) |
    (1 << CGEventType.rightMouseUp.rawValue)   |
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.otherMouseUp.rawValue)   |
    (1 << CGEventType.scrollWheel.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: callback,
    userInfo: nil
) else {
    FileHandle.standardError.write(Data("debug-buttons: tap create failed — Accessibility not active\n".utf8))
    exit(1)
}
sharedTap = tap

let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("debug-buttons: listening. Press every mouse button. Ctrl-C to quit.")
CFRunLoopRun()
