// Records what is in front on this Mac, as it changes, to one local file per day. Nothing leaves the machine.
//
//   ~/.claude-time/tracker/<date>.jsonl     one JSON object per line, appended and flushed as it happens
//
// Events: start, stop, focus (app, window, Ghostty tab and directory), heartbeat (idle seconds), sleep, wake,
// poweroff, lock, unlock, note. It records facts and decides nothing: idle seconds are written as they are.
//
// Needs Accessibility permission for window titles, and Automation permission to ask Ghostty for its tabs.
// Run with --prompt to have macOS ask for Accessibility. Set TRACKER_DIR to write somewhere else.
import AppKit
import ApplicationServices
import Foundation

let dataDir = ProcessInfo.processInfo.environment["TRACKER_DIR"]
    ?? (NSString(string: "~/.claude-time/tracker").expandingTildeInPath as String)
let heartbeatSeconds: TimeInterval = 30
let settleSeconds: TimeInterval = 0.4
let ghosttyBundle = "com.mitchellh.ghostty"

let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = .current
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    return formatter
}()

final class EventLog {
    private var handle: FileHandle?
    private var day = ""

    func write(_ type: String, _ fields: [String: Any] = [:]) {
        let now = Date()
        var line = fields
        line["t"] = isoFormatter.string(from: now)
        line["type"] = type
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        let today = dayFormatter.string(from: now)
        if today != day || handle == nil {
            openFile(for: today)
        }
        try? handle?.write(contentsOf: data + Data([0x0A]))
        try? handle?.synchronize()
    }

    private func openFile(for today: String) {
        try? handle?.close()
        let manager = FileManager.default
        try? manager.createDirectory(atPath: dataDir, withIntermediateDirectories: true,
                                     attributes: [.posixPermissions: 0o700])
        let path = "\(dataDir)/\(today).jsonl"
        if !manager.fileExists(atPath: path) {
            manager.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        handle = FileHandle(forWritingAtPath: path)
        _ = try? handle?.seekToEnd()
        day = today
    }
}

let log = EventLog()
var accessibilityTrusted = false
var ghosttyErrorReported = false

func idleSeconds() -> Int {
    Int(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!))
}

/// Terminals put a spinner or status glyph in front of the title ("✳ name", "◑ name"). Split it off so a
/// changing glyph does not look like a different window.
func splitMarker(_ title: String) -> (marker: String?, rest: String) {
    let scalars = Array(title.unicodeScalars)
    var end = 0
    while end < scalars.count, CharacterSet.symbols.contains(scalars[end]) { end += 1 }
    guard end > 0, end < scalars.count, scalars[end] == " " else { return (nil, title) }
    let marker = String(String.UnicodeScalarView(scalars[0..<end]))
    let rest = String(String.UnicodeScalarView(scalars[(end + 1)...]))
    return (marker, rest)
}

func focusedWindowTitle(pid: pid_t) -> String? {
    let app = AXUIElementCreateApplication(pid)
    var window: AnyObject?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
          let element = window else { return nil }
    var title: AnyObject?
    guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
    else { return nil }
    return title as? String
}

func queryGhostty() -> [String: String]? {
    let source = """
    tell application "Ghostty"
        set t to focused terminal of selected tab of front window
        return (id of t) & "\t" & (name of t) & "\t" & (working directory of t)
    end tell
    """
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return nil }
    let result = script.executeAndReturnError(&error)
    if let error = error {
        if !ghosttyErrorReported {
            ghosttyErrorReported = true
            log.write("note", ["message": "Ghostty query failed", "detail": "\(error)"])
        }
        return nil
    }
    guard let text = result.stringValue else { return nil }
    let parts = text.components(separatedBy: "\t")
    guard parts.count == 3 else { return nil }
    return ["id": parts[0], "name": splitMarker(parts[1]).rest, "cwd": parts[2]]
}

func currentFocus() -> [String: Any] {
    guard let app = NSWorkspace.shared.frontmostApplication else { return [:] }
    var focus: [String: Any] = ["app": app.localizedName ?? "?", "bundle": app.bundleIdentifier ?? "?",
                                "pid": Int(app.processIdentifier)]
    if accessibilityTrusted, let raw = focusedWindowTitle(pid: app.processIdentifier) {
        focus["window"] = splitMarker(raw).rest
    }
    if app.bundleIdentifier == ghosttyBundle, let tab = queryGhostty() {
        focus["ghostty"] = tab
    }
    return focus
}

var lastFocusKey = ""

func logFocusIfChanged() {
    let focus = currentFocus()
    guard !focus.isEmpty,
          let data = try? JSONSerialization.data(withJSONObject: focus, options: [.sortedKeys]),
          let key = String(data: data, encoding: .utf8), key != lastFocusKey else { return }
    lastFocusKey = key
    log.write("focus", focus)
}

// Window and tab changes come as events from the focused app. A burst of changes (flicking through tabs)
// settles for a moment and then writes once.
var observer: AXObserver?
var observedPID: pid_t = 0
var watchedWindow: AXUIElement?
var settleTimer: Timer?

let accessibilityCallback: AXObserverCallback = { _, _, _, _ in scheduleSnapshot() }

func scheduleSnapshot() {
    settleTimer?.invalidate()
    settleTimer = Timer.scheduledTimer(withTimeInterval: settleSeconds, repeats: false) { _ in
        watchFocusedWindowTitle()
        logFocusIfChanged()
    }
}

func stopObserving() {
    if let observer = observer {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
    observer = nil
    watchedWindow = nil
}

func observe(pid: pid_t) {
    stopObserving()
    guard accessibilityTrusted else { return }
    var created: AXObserver?
    guard AXObserverCreate(pid, accessibilityCallback, &created) == .success, let newObserver = created else { return }
    let app = AXUIElementCreateApplication(pid)
    AXObserverAddNotification(newObserver, app, kAXFocusedWindowChangedNotification as CFString, nil)
    AXObserverAddNotification(newObserver, app, kAXMainWindowChangedNotification as CFString, nil)
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
    observer = newObserver
    observedPID = pid
    watchFocusedWindowTitle()
}

func watchFocusedWindowTitle() {
    guard let observer = observer else { return }
    if let old = watchedWindow {
        AXObserverRemoveNotification(observer, old, kAXTitleChangedNotification as CFString)
    }
    var window: AnyObject?
    let app = AXUIElementCreateApplication(observedPID)
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
          let element = window else { return }
    let windowElement = element as! AXUIElement
    AXObserverAddNotification(observer, windowElement, kAXTitleChangedNotification as CFString, nil)
    watchedWindow = windowElement
}

func heartbeat() {
    var fields: [String: Any] = ["idle_s": idleSeconds()]
    if let app = NSWorkspace.shared.frontmostApplication {
        fields["app"] = app.localizedName ?? "?"
        if accessibilityTrusted, let raw = focusedWindowTitle(pid: app.processIdentifier) {
            fields["window_raw"] = raw
        }
    }
    log.write("heartbeat", fields)
}

// --- start up

accessibilityTrusted = CommandLine.arguments.contains("--prompt")
    ? AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    : AXIsProcessTrusted()
log.write("start", ["pid": Int(ProcessInfo.processInfo.processIdentifier), "accessibility": accessibilityTrusted,
                    "data_dir": dataDir])
if !accessibilityTrusted {
    FileHandle.standardError.write(Data("No Accessibility permission, so window titles are not recorded. Run with --prompt.\n".utf8))
}
FileHandle.standardError.write(Data("Recording to \(dataDir). Stop with Ctrl-C.\n".utf8))

let workspaceCenter = NSWorkspace.shared.notificationCenter
workspaceCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
    if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        observe(pid: app.processIdentifier)
    }
    scheduleSnapshot()
}
workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
    log.write("sleep", ["idle_s": idleSeconds()])
}
workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
    log.write("wake")
    lastFocusKey = ""
    scheduleSnapshot()
}
workspaceCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
    log.write("poweroff")
}
let distributedCenter = DistributedNotificationCenter.default()
distributedCenter.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
    log.write("lock")
}
distributedCenter.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
    log.write("unlock")
    lastFocusKey = ""
    scheduleSnapshot()
}

Timer.scheduledTimer(withTimeInterval: heartbeatSeconds, repeats: true) { _ in heartbeat() }

var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGINT, SIGTERM] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        log.write("stop", ["reason": "signal"])
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

if let front = NSWorkspace.shared.frontmostApplication {
    observe(pid: front.processIdentifier)
}
logFocusIfChanged()

NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
