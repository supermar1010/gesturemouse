import Foundation
import CoreGraphics
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Config

struct ActionSpec: Decodable {
    let key: String
    let mods: [String]
}

struct ScrollInvertConfig: Decodable {
    let verticalMouseOnly: Bool
}

struct Config: Decodable {
    let button: Int
    let moveThreshold: Double
    let actions: [String: ActionSpec]
    let scrollInvert: ScrollInvertConfig?
}

let defaultConfigJSON = """
{
  "button": 5,
  "moveThreshold": 25,
  "actions": {
    "click": { "key": "up",    "mods": ["ctrl"] },
    "left":  { "key": "left",  "mods": ["ctrl"] },
    "right": { "key": "right", "mods": ["ctrl"] },
    "up":    { "key": "4",     "mods": ["cmd", "shift"] },
    "down":  { "key": "down",  "mods": ["ctrl"] }
  },
  "scrollInvert": {
    "verticalMouseOnly": true
  }
}
"""

func loadConfig() -> Config {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dir  = home.appendingPathComponent(".config/gesturemouse", isDirectory: true)
    let file = dir.appendingPathComponent("config.json")

    if !FileManager.default.fileExists(atPath: file.path) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? defaultConfigJSON.write(to: file, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("gesturemouse: wrote default config to \(file.path)\n".utf8))
    }

    do {
        let data = try Data(contentsOf: file)
        return try JSONDecoder().decode(Config.self, from: data)
    } catch {
        FileHandle.standardError.write(Data("gesturemouse: config parse failed (\(error)), using defaults\n".utf8))
        let data = Data(defaultConfigJSON.utf8)
        return try! JSONDecoder().decode(Config.self, from: data)
    }
}

let config = loadConfig()

// MARK: - Key/mod tables

let keyMap: [String: CGKeyCode] = [
    "left":   CGKeyCode(kVK_LeftArrow),
    "right":  CGKeyCode(kVK_RightArrow),
    "up":     CGKeyCode(kVK_UpArrow),
    "down":   CGKeyCode(kVK_DownArrow),
    "space":  CGKeyCode(kVK_Space),
    "return": CGKeyCode(kVK_Return),
    "tab":    CGKeyCode(kVK_Tab),
    "esc":    CGKeyCode(kVK_Escape),
    "delete": CGKeyCode(kVK_Delete),
    "0":      CGKeyCode(kVK_ANSI_0),
    "1":      CGKeyCode(kVK_ANSI_1),
    "2":      CGKeyCode(kVK_ANSI_2),
    "3":      CGKeyCode(kVK_ANSI_3),
    "4":      CGKeyCode(kVK_ANSI_4),
    "5":      CGKeyCode(kVK_ANSI_5),
    "6":      CGKeyCode(kVK_ANSI_6),
    "7":      CGKeyCode(kVK_ANSI_7),
    "8":      CGKeyCode(kVK_ANSI_8),
    "9":      CGKeyCode(kVK_ANSI_9),
    "f1":  CGKeyCode(kVK_F1),  "f2":  CGKeyCode(kVK_F2),
    "f3":  CGKeyCode(kVK_F3),  "f4":  CGKeyCode(kVK_F4),
    "f5":  CGKeyCode(kVK_F5),  "f6":  CGKeyCode(kVK_F6),
    "f7":  CGKeyCode(kVK_F7),  "f8":  CGKeyCode(kVK_F8),
    "f9":  CGKeyCode(kVK_F9),  "f10": CGKeyCode(kVK_F10),
    "f11": CGKeyCode(kVK_F11), "f12": CGKeyCode(kVK_F12),
]

let modMap: [String: CGEventFlags] = [
    "cmd":   .maskCommand,
    "shift": .maskShift,
    "ctrl":  .maskControl,
    "alt":   .maskAlternate,
    "opt":   .maskAlternate,
]

let modKeyCodes: [String: CGKeyCode] = [
    "cmd":   CGKeyCode(kVK_Command),
    "shift": CGKeyCode(kVK_Shift),
    "ctrl":  CGKeyCode(kVK_Control),
    "alt":   CGKeyCode(kVK_Option),
    "opt":   CGKeyCode(kVK_Option),
]

// MARK: - Keystroke synthesis

let sendQueue = DispatchQueue(label: "gesturemouse.send")

func sendKey(_ spec: ActionSpec) {
    guard let code = keyMap[spec.key.lowercased()] else {
        FileHandle.standardError.write(Data("gesturemouse: unknown key '\(spec.key)'\n".utf8))
        return
    }
    FileHandle.standardError.write(Data("gesturemouse: sendKey key=\(spec.key) mods=\(spec.mods)\n".utf8))
    let flags = spec.mods.reduce(CGEventFlags()) { acc, m in
        acc.union(modMap[m.lowercased()] ?? CGEventFlags())
    }

    // Dispatch off the event-tap callback thread. Use null source + flags
    // only (Hammerspoon's recipe). Post at session tap.
    sendQueue.async {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cgSessionEventTap)
        usleep(2000)

        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cgSessionEventTap)
    }
}

// MARK: - Gesture state

var gestureActive = false
var accDx: CGFloat = 0
var accDy: CGFloat = 0

func beginGesture() {
    gestureActive = true
    accDx = 0
    accDy = 0
    // Decouple HID input from the visible cursor so the pointer stays put
    // while the user drags the gesture button. Re-coupled on release.
    CGAssociateMouseAndMouseCursorPosition(0)
}

func endGesture() {
    CGAssociateMouseAndMouseCursorPosition(1)
    gestureActive = false
}

func classify(dx: CGFloat, dy: CGFloat) -> String {
    let ax = abs(dx), ay = abs(dy)
    if ax < CGFloat(config.moveThreshold) && ay < CGFloat(config.moveThreshold) {
        return "click"
    }
    if ax > ay {
        return dx < 0 ? "left" : "right"
    }
    return dy < 0 ? "up" : "down"
}

// MARK: - Event tap callback

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if gestureActive { endGesture() }
        DispatchQueue.main.async {
            if let tap = sharedTap { CGEvent.tapEnable(tap: tap, enable: true) }
        }
        return Unmanaged.passUnretained(event)
    }

    if type == .scrollWheel {
        guard let invert = config.scrollInvert, invert.verticalMouseOnly else {
            return Unmanaged.passUnretained(event)
        }
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        if isContinuous != 0 { return Unmanaged.passUnretained(event) }  // trackpad

        let d1  = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let pd1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fp1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1,      value: -d1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pd1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fp1)
        return Unmanaged.passUnretained(event)
    }

    // While the gesture button is held, accumulate movement deltas and swallow
    // the move events so the cursor stays frozen even if our decouple call
    // didn't take effect (belt + suspenders).
    if gestureActive &&
        (type == .otherMouseDragged || type == .mouseMoved ||
         type == .leftMouseDragged  || type == .rightMouseDragged) {
        accDx += CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
        accDy += CGFloat(event.getIntegerValueField(.mouseEventDeltaY))
        return nil
    }

    if type == .otherMouseDown || type == .otherMouseUp {
        let btn = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        if btn != config.button { return Unmanaged.passUnretained(event) }

        if type == .otherMouseDown {
            beginGesture()
            return nil
        }
        if type == .otherMouseUp && gestureActive {
            let dx = accDx, dy = accDy
            endGesture()
            let dir = classify(dx: dx, dy: dy)
            if let action = config.actions[dir] { sendKey(action) }
            return nil
        }
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - Accessibility prompt

func ensureAccessibility() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let opts = [key: true] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(opts)
    if !trusted {
        FileHandle.standardError.write(Data("gesturemouse: Accessibility not granted yet. macOS opened System Settings; toggle the switch for 'gesturemouse', then re-run.\n".utf8))
        exit(2)
    }
}

ensureAccessibility()

// MARK: - Bootstrap

var sharedTap: CFMachPort? = nil

let mask: CGEventMask =
    (1 << CGEventType.otherMouseDown.rawValue)    |
    (1 << CGEventType.otherMouseUp.rawValue)      |
    (1 << CGEventType.otherMouseDragged.rawValue) |
    (1 << CGEventType.mouseMoved.rawValue)        |
    (1 << CGEventType.leftMouseDragged.rawValue)  |
    (1 << CGEventType.rightMouseDragged.rawValue) |
    (1 << CGEventType.scrollWheel.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: mask,
    callback: callback,
    userInfo: nil
) else {
    FileHandle.standardError.write(Data("gesturemouse: event tap create failed — grant Accessibility permission in System Settings → Privacy & Security → Accessibility\n".utf8))
    exit(1)
}
sharedTap = tap

let runLoopSrc = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSrc, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

FileHandle.standardError.write(Data("gesturemouse: running (button=\(config.button), threshold=\(config.moveThreshold))\n".utf8))

CFRunLoopRun()
