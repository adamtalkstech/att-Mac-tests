// ATT memory bandwidth, GPU side (Metal copy kernel on a big buffer). Nov 21 2026.
import Metal
import Foundation
let mb = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1])! : 1024
guard let dev = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(1) }
let src = """
#include <metal_stdlib>
using namespace metal;
kernel void copy4(device const float4* a [[buffer(0)]], device float4* b [[buffer(1)]], uint i [[thread_position_in_grid]]) { b[i] = a[i]; }
"""
let lib = try! dev.makeLibrary(source: src, options: nil)
let pso = try! dev.makeComputePipelineState(function: lib.makeFunction(name: "copy4")!)
let bytes = mb * 1024 * 1024
let a = dev.makeBuffer(length: bytes, options: .storageModePrivate)!
let b = dev.makeBuffer(length: bytes, options: .storageModePrivate)!
let q = dev.makeCommandQueue()!
let n = bytes / 16
func once() -> Double {
  let cb = q.makeCommandBuffer()!; let e = cb.makeComputeCommandEncoder()!
  e.setComputePipelineState(pso); e.setBuffer(a, offset: 0, index: 0); e.setBuffer(b, offset: 0, index: 1)
  let w = pso.maxTotalThreadsPerThreadgroup
  e.dispatchThreads(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1))
  e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
  return cb.gpuEndTime - cb.gpuStartTime }
_ = once()
var best = 1e9; for _ in 0..<20 { best = min(best, once()) }
print(String(format: "GPU copy GB/s: %.1f", Double(2 * bytes) / best / 1e9))
print("GPU: \(dev.name)  buffer MB: \(mb)")
