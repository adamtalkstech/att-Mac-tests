// att-axfind: find a UI element in an app by its name and double-click it (Nov 23 2026).
// Replaces AppleScript's "entire contents" crawl (which beachballed Final Cut for minutes):
// this walks the Accessibility tree inside one process, depth- and count-limited, with a time cap.
//   att-axfind <pid> "<name>" [seconds]   -> double-clicks the first match, prints "OK x y" or "NOTFOUND"
import ApplicationServices
import CoreGraphics
import Foundation
let a = CommandLine.arguments
guard a.count >= 3, let pid = Int32(a[1]) else { print("usage: att-axfind PID NAME [secs]"); exit(2) }
let want = a[2].lowercased(), limit = a.count > 3 ? Double(a[3]) ?? 20 : 20
let t0 = Date(); var seen = 0
func str(_ e: AXUIElement, _ k: String) -> String? {
  var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success else { return nil }
  return v as? String }
func kids(_ e: AXUIElement) -> [AXUIElement] {
  var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) == .success else { return [] }
  return (v as? [AXUIElement]) ?? [] }
func frame(_ e: AXUIElement) -> CGRect? {
  var p: CFTypeRef?, s: CFTypeRef?; var pt = CGPoint.zero, sz = CGSize.zero
  guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &p) == .success,
        AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &s) == .success else { return nil }
  AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(s as! AXValue, .cgSize, &sz)
  return CGRect(origin: pt, size: sz) }
func find(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
  if depth > 30 || seen > 15000 || Date().timeIntervalSince(t0) > limit { return nil }
  seen += 1
  if str(e, kAXRoleAttribute) != "AXTextField" {
    for k in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
      if let s = str(e, k), s.lowercased() == want, let f = frame(e), f.width > 4, f.height > 4 { return e } } }
  for c in kids(e) { if let r = find(c, depth + 1) { return r } }
  return nil }
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 1)   // Nov 23: 1 s per call, 15k items max
var wins: CFTypeRef?
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &wins)
for w in (wins as? [AXUIElement]) ?? [] {
  if let hit = find(w, 0), let f = frame(hit) {
    let p = CGPoint(x: f.midX, y: f.midY)
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(150_000)
    for i in 1...2 { for t in [CGEventType.leftMouseDown, .leftMouseUp] {
      let ev = CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)
      ev?.setIntegerValueField(.mouseEventClickState, value: Int64(i)); ev?.post(tap: .cghidEventTap); usleep(30_000) }; usleep(60_000) }
    print("OK \(Int(p.x)) \(Int(p.y)) (\(seen) items checked)"); exit(0) }
}
print("NOTFOUND (\(seen) items checked in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s)")
