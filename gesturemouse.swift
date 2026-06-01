import Foundation
import CoreGraphics
import Carbon.HIToolbox
import ApplicationServices
import AppKit

// MARK: - Config

struct ActionSpec: Decodable {
    let key: String
    let mods: [String]
}

struct ScrollInvertConfig: Decodable {
    let verticalMouseOnly: Bool?
    let horizontalMouseOnly: Bool?
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
    "verticalMouseOnly": true,
    "horizontalMouseOnly": false
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

let osaModName: [String: String] = [
    "cmd":   "command down",
    "shift": "shift down",
    "ctrl":  "control down",
    "alt":   "option down",
    "opt":   "option down",
]

func scriptSource(for spec: ActionSpec) -> String? {
    guard let code = keyMap[spec.key.lowercased()] else { return nil }
    let modParts = spec.mods.compactMap { osaModName[$0.lowercased()] }
    let usingClause = modParts.isEmpty ? "" : " using {\(modParts.joined(separator: ", "))}"
    return "tell application \"System Events\" to key code \(code)\(usingClause)"
}

// Pre-compile NSAppleScript per direction so each gesture only pays the
// AppleEvent round-trip (~5-10 ms) rather than osascript subprocess spawn
// + compile (~50-100 ms). Routing through System Events is still needed —
// raw CGEventPost loses the Ctrl modifier for symbolic hotkeys like
// Mission Control and Spaces switching.
var compiledScripts: [String: NSAppleScript] = [:]

func compileScripts() {
    for (dir, spec) in config.actions {
        guard let source = scriptSource(for: spec) else { continue }
        let script = NSAppleScript(source: source)
        var err: NSDictionary? = nil
        if script?.compileAndReturnError(&err) == true {
            compiledScripts[dir] = script
        } else {
            FileHandle.standardError.write(Data("gesturemouse: compile failed for '\(dir)': \(err ?? [:])\n".utf8))
        }
    }
}

func sendAction(dir: String) {
    guard let script = compiledScripts[dir] else {
        FileHandle.standardError.write(Data("gesturemouse: no compiled script for '\(dir)'\n".utf8))
        return
    }
    sendQueue.async {
        var err: NSDictionary? = nil
        script.executeAndReturnError(&err)
        if let err = err {
            FileHandle.standardError.write(Data("gesturemouse: exec error for '\(dir)': \(err)\n".utf8))
        }
    }
}

// MARK: - Gesture state

var gestureActive = false
var gestureFired = false
var accDx: CGFloat = 0
var accDy: CGFloat = 0
var anchorPos: CGPoint = .zero

func beginGesture() {
    gestureActive = true
    gestureFired = false
    accDx = 0
    accDy = 0
    anchorPos = CGEvent(source: nil)?.location ?? .zero
    // Decouple HID input from the visible cursor. On many setups this alone
    // is enough; on others (e.g. Logitech HID++ devices reporting absolute
    // positions) it has no effect, so we also warp the cursor back on every
    // move event while the gesture button is held.
    CGAssociateMouseAndMouseCursorPosition(0)
}

func endGesture() {
    CGAssociateMouseAndMouseCursorPosition(1)
    gestureActive = false
}

func directionOf(dx: CGFloat, dy: CGFloat) -> String {
    if abs(dx) > abs(dy) {
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
        guard let invert = config.scrollInvert else {
            return Unmanaged.passUnretained(event)
        }
        let invV = invert.verticalMouseOnly ?? false
        let invH = invert.horizontalMouseOnly ?? false
        if !invV && !invH { return Unmanaged.passUnretained(event) }
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        if isContinuous != 0 { return Unmanaged.passUnretained(event) }  // trackpad

        if invV {
            let d1  = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let pd1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let fp1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1,      value: -d1)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pd1)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fp1)
        }
        if invH {
            let d2  = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let pd2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let fp2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2,      value: -d2)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -pd2)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fp2)
        }
        return Unmanaged.passUnretained(event)
    }

    // While the gesture button is held, accumulate movement deltas and swallow
    // the move events so the cursor stays frozen even if our decouple call
    // didn't take effect (belt + suspenders). Fire the direction action as soon
    // as the threshold is crossed (Logitech Options+ behavior), then ignore
    // further motion until the button is released.
    if gestureActive &&
        (type == .otherMouseDragged || type == .mouseMoved ||
         type == .leftMouseDragged  || type == .rightMouseDragged) {
        // After the action has fired, release the cursor and pass motion through
        // so the user can keep moving the mouse freely while still holding the
        // gesture button. This matches Logitech Options+ behavior.
        if gestureFired {
            return Unmanaged.passUnretained(event)
        }
        accDx += CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
        accDy += CGFloat(event.getIntegerValueField(.mouseEventDeltaY))
        CGWarpMouseCursorPosition(anchorPos)
        let t = CGFloat(config.moveThreshold)
        if abs(accDx) >= t || abs(accDy) >= t {
            let dir = directionOf(dx: accDx, dy: accDy)
            gestureFired = true
            CGAssociateMouseAndMouseCursorPosition(1)
            if config.actions[dir] != nil { sendAction(dir: dir) }
        }
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
            let fired = gestureFired
            endGesture()
            if !fired, config.actions["click"] != nil { sendAction(dir: "click") }
            return nil
        }
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - Accessibility prompt

// macOS caches the result of `AXIsProcessTrusted` per process, so once it
// has returned false it keeps returning false even after the user toggles
// the switch. We therefore use `CGEvent.tapCreate` itself as the probe in
// the bootstrap loop below — it tests the real capability we need and
// picks up newly-granted permission in the same process when the cache
// lets us. As a fallback for cache-stuck processes, the loop exits after
// 60s so `brew services keep_alive` (or a manual re-run) starts a fresh
// process whose trust state is re-read from TCC.
func promptForAccessibility() {
    if AXIsProcessTrusted() { return }
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
}

promptForAccessibility()
compileScripts()

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

func acquireTap() -> CFMachPort {
    var notified = false
    var waited = 0
    while true {
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) {
            if notified {
                FileHandle.standardError.write(Data("gesturemouse: Accessibility granted, continuing.\n".utf8))
            }
            return tap
        }
        if !notified {
            FileHandle.standardError.write(Data("gesturemouse: waiting for Accessibility permission. Toggle gesturemouse in System Settings → Privacy & Security → Accessibility.\n".utf8))
            notified = true
        }
        Thread.sleep(forTimeInterval: 2.0)
        waited += 2
        if waited >= 60 {
            FileHandle.standardError.write(Data("gesturemouse: tap still unavailable after 60s — exiting so brew services / launchd restarts the process with a fresh trust check.\n".utf8))
            exit(75)  // EX_TEMPFAIL — keep_alive will restart
        }
    }
}

let tap = acquireTap()
sharedTap = tap

let runLoopSrc = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSrc, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

FileHandle.standardError.write(Data("gesturemouse: running (button=\(config.button), threshold=\(config.moveThreshold))\n".utf8))

CFRunLoopRun()
