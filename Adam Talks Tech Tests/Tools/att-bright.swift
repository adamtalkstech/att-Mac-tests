// att-bright: read / set the built-in display's brightness (0.0-1.0) for the battery experiment (Nov 22 2026)
//   att-bright          prints the current level
//   att-bright 0.5      sets it, then prints it
import Foundation
import CoreGraphics
guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
      let ps = dlsym(h, "DisplayServicesSetBrightness"), let pg = dlsym(h, "DisplayServicesGetBrightness") else { print("-1"); exit(1) }
typealias SetF = @convention(c) (UInt32, Float) -> Int32
typealias GetF = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
let setB = unsafeBitCast(ps, to: SetF.self), getB = unsafeBitCast(pg, to: GetF.self)
let d = CGMainDisplayID()
if CommandLine.arguments.count > 1, let v = Float(CommandLine.arguments[1]) { _ = setB(d, max(0, min(1, v))) }
var cur: Float = -1
_ = getB(d, &cur)
print(String(format: "%.3f", cur))
