// att-snappy: millisecond timer for the Responsiveness test (v2, Nov 22 2026)
// v1 timed everything through osascript, which can't measure under ~230 ms, so every
// M5 Pro/Max scored 1000. This one is compiled, runs inside one process, and measures:
//   app <Name>  -> time from "switch to it" until the app answers (its main thread is free)
//                  AND its window is the front window on screen. Prints "<ms> <rc>"
//   tab <N>     -> time from "switch Safari to tab N" until that page has painted a frame
//                  (or, if macOS threw the tab away, until the reloaded page first paints).
//                  Prints "<ms> <rc> <reloaded 0/1>"
// Built once per Mac into ~/.att/att-snappy by att-responsiveness.zsh (needs Command Line Tools).
import AppKit
import ApplicationServices
import Foundation

setvbuf(stdout, nil, _IONBF, 0)
func up() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }
func epoch() -> Double { Date().timeIntervalSince1970 * 1000 }
func spin(_ ms: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: ms / 1000)) }
func compiled(_ src: String) -> NSAppleScript? {
    guard let s = NSAppleScript(source: src) else { return nil }
    var e: NSDictionary?
    return s.compileAndReturnError(&e) ? s : nil
}
func run(_ s: NSAppleScript) -> (String?, Bool) {
    var e: NSDictionary?
    let r = s.executeAndReturnError(&e)
    return (r.stringValue, e == nil)
}
// pid of the app that owns the front-most normal window on screen
func frontWindowOwner() -> pid_t? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in list {
        guard (w[kCGWindowLayer as String] as? Int) == 0 else { continue }
        if let a = w[kCGWindowAlpha as String] as? Double, a < 0.1 { continue }
        if let b = w[kCGWindowBounds as String] as? [String: Double], (b["Width"] ?? 0) < 80 || (b["Height"] ?? 0) < 80 { continue }
        return w[kCGWindowOwnerPID as String] as? pid_t
    }
    return nil
}

let a = CommandLine.arguments
guard a.count >= 3 else { print("usage: att-snappy app <Name> | tab <N>"); exit(2) }
let LIMIT = 20000.0   // give up after 20 s

switch a[1] {
case "app":
    let name = a[2]
    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else { print("-1 1"); exit(0) }
    let pid = app.processIdentifier
    let ax = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(ax, Float(LIMIT / 1000))
    let target = (app.bundleIdentifier.map { "application id \"\($0)\"" }) ?? "application \"\(name)\""
    guard let act = compiled("tell \(target) to activate") else { print("-1 1"); exit(0) }
    let t0 = up()
    _ = run(act)
    // 1. the app answers: a swapped-out or busy app can't reply until its main thread is free
    var v: CFTypeRef?
    let ok = AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &v) == .success
    let answered = up() - t0
    guard ok else { print(String(format: "%.0f 1", answered)); exit(0) }
    // 2. its window is really in front on screen (skipped for an app with no windows open)
    var drawn = answered
    if ((v as? [AXUIElement])?.count ?? 0) > 0 {
        drawn = -1
        while up() - t0 < LIMIT { if frontWindowOwner() == pid { drawn = up() - t0; break }; spin(1) }
    }
    if drawn < 0 { print(String(format: "%.0f 1", up() - t0)); exit(0) }
    print(String(format: "%.0f 0", max(answered, drawn)))

case "tab":
    let n = Int(a[2]) ?? 1
    if let s = compiled("tell application \"Safari\" to activate") { _ = run(s) }   // not timed
    spin(400)
    guard let sw = compiled("tell application \"Safari\" to set current tab of front window to tab \(n) of front window"),
          let q = compiled(#"tell application "Safari" to do JavaScript "JSON.stringify([window.__att?1:0,(window.__attShows||[]).slice(-1)[0]||0,performance.timeOrigin,((performance.getEntriesByType('paint').filter(function(p){return p.name=='first-contentful-paint'})[0])||{startTime:0}).startTime])" in current tab of front window"#)
    else { print("-1 1 0"); exit(0) }
    let t0e = epoch(), t0 = up()
    guard run(sw).1 else { print("-1 1 0"); exit(0) }
    var firstAnswer = -1.0
    while up() - t0 < LIMIT {
        let (s, ok) = run(q)
        if ok, let s = s, let d = s.data(using: .utf8),
           let arr = (try? JSONSerialization.jsonObject(with: d)) as? [NSNumber], arr.count == 4 {
            if firstAnswer < 0 { firstAnswer = up() - t0 }
            let kept = arr[0].intValue == 1, shown = arr[1].doubleValue, origin = arr[2].doubleValue, fcp = arr[3].doubleValue
            if kept && shown > t0e { print(String(format: "%.0f 0 0", shown - t0e)); exit(0) }
            if !kept {
                if origin + fcp > t0e && fcp > 0 { print(String(format: "%.0f 0 1", origin + fcp - t0e)); exit(0) }
                if origin < t0e - 500 { print(String(format: "%.0f 0 1", firstAnswer)); exit(0) }   // reloaded earlier, in the background
            }
            // kept but no frame recorded (tab was already in front, or no listener): time to first answer
            if kept && up() - t0 > 2000 { print(String(format: "%.0f 0 0", firstAnswer)); exit(0) }
        }
        spin(15)
    }
    print(String(format: "%.0f 1 0", up() - t0))

default:
    print("usage: att-snappy app <Name> | tab <N>"); exit(2)
}
