// CI helper for scripts/visual-qa/run.sh (GitHub-hosted macOS runners only; not part of the app).
//   windows <pid>        one line per on-screen window of that process: id layer x y w h
//   windows screen       main display size in points: w h
//   windows luma <png>   mean luma (0-255) of the image's non-transparent pixels, to sanity-check light vs dark
// Window bounds and ids come from CGWindowList and need no Screen Recording permission.
import CoreGraphics
import Foundation
import ImageIO

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "screen":
    let bounds = CGDisplayBounds(CGMainDisplayID())
    print(Int(bounds.width), Int(bounds.height))
case "luma":
    guard args.count == 2,
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { exit(1) }
    // Downscale into a small RGBA buffer; transparent pixels (window corners) are left out of the mean.
    let side = 64
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return true
    }
    guard drawn else { exit(1) }
    var total = 0.0, weight = 0.0
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = Double(pixels[i + 3]) / 255
        guard alpha > 0.5 else { continue }
        // Un-premultiply, then Rec. 601 luma.
        let r = Double(pixels[i]) / alpha, g = Double(pixels[i + 1]) / alpha, b = Double(pixels[i + 2]) / alpha
        total += 0.299 * r + 0.587 * g + 0.114 * b
        weight += 1
    }
    guard weight > 0 else { exit(1) }
    print(Int((total / weight).rounded()))
case let pid?:
    guard let owner = Int(pid) else { exit(64) }
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in info where (window[kCGWindowOwnerPID as String] as? Int) == owner {
        let id = window[kCGWindowNumber as String] as? Int ?? 0
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
        print(id, layer, Int(bounds["X"] ?? 0), Int(bounds["Y"] ?? 0), Int(bounds["Width"] ?? 0), Int(bounds["Height"] ?? 0))
    }
default:
    exit(64)
}
