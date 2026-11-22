// ATT click helper: double-click (or click) at screen point x y. Used to open the Final Cut
// project (opening a library doesn't open its project). Needs Terminal in Accessibility.
// Build: swiftc -O att-click.swift -o ~/.att/att-click   Use: att-click X Y [clicks]
import CoreGraphics
import Foundation
let a = CommandLine.arguments
guard a.count >= 3, let x = Double(a[1]), let y = Double(a[2]) else { print("usage: att-click X Y [clicks]"); exit(1) }
let n = a.count > 3 ? Int(a[3]) ?? 2 : 2
let p = CGPoint(x: x, y: y)
let src = CGEventSource(stateID: .hidSystemState)
CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(150_000)
for i in 1...n {
  for t in [CGEventType.leftMouseDown, .leftMouseUp] {
    let e = CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)
    e?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
    e?.post(tap: .cghidEventTap)
    usleep(30_000)
  }
  usleep(60_000)
}
