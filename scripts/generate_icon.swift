// Generates the Nimble Fuji app icon master (Nimble Icons style guide v2).
// Concept: "the camera does the rendering" — a cream X-T5-style body (centred
// viewfinder hump, top dial) with the lens cut in as concentric Nimble Blue rings.
//
// Usage: swift scripts/generate_icon.swift <output.png>
// Prints a pixel check of the background corners and the mark.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let nimbleBlue = CGColor(srgbRed: 0 / 255, green: 154 / 255, blue: 214 / 255, alpha: 1)  // #009AD6
let deepBlue = CGColor(srgbRed: 0 / 255, green: 108 / 255, blue: 165 / 255, alpha: 1)    // #006CA5
let cream = CGColor(srgbRed: 250 / 255, green: 248 / 255, blue: 244 / 255, alpha: 1)     // #FAF8F4

/// Closed polygon with each corner rounded by its own radius.
func roundedPolygon(_ points: [CGPoint], radii: [CGFloat]) -> CGPath {
    let path = CGMutablePath()
    let n = points.count
    path.move(to: CGPoint(x: (points[n - 1].x + points[0].x) / 2, y: (points[n - 1].y + points[0].y) / 2))
    for i in 0..<n {
        path.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % n], radius: radii[i])
    }
    path.closeSubpath()
    return path
}

func circle(center: CGPoint, diameter d: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d), transform: nil)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                    space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// Background: diagonal gradient, Nimble Blue top-left → Deep Blue bottom-right.
let gradient = CGGradient(colorsSpace: srgb, colors: [nimbleBlue, deepBlue] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// 512 grid, top-left origin.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 2, y: -2)

ctx.setFillColor(cream)

// Body: 336 × 204 (66% of the width), soft corners like the family's rounded rects.
let body = CGRect(x: 88, y: 186, width: 336, height: 204)
ctx.addPath(roundedRect(body, radius: 46))
// Viewfinder hump: centred trapezoid that merges into the body.
ctx.addPath(roundedPolygon([
    CGPoint(x: 196, y: 196),
    CGPoint(x: 220, y: 132),
    CGPoint(x: 292, y: 132),
    CGPoint(x: 316, y: 196),
], radii: [0, 16, 16, 0]))
// Top dial on the left shoulder.
ctx.addPath(roundedRect(CGRect(x: 118, y: 160, width: 58, height: 40), radius: 12))
ctx.fillPath()

// Lens: concentric rings cut in with Nimble Blue (outer ring, cream barrel, blue glass).
let lensCenter = CGPoint(x: 256, y: 292)
ctx.setFillColor(nimbleBlue)
ctx.addPath(circle(center: lensCenter, diameter: 168))
ctx.fillPath()
ctx.setFillColor(cream)
ctx.addPath(circle(center: lensCenter, diameter: 124))
ctx.fillPath()
ctx.setFillColor(nimbleBlue)
ctx.addPath(circle(center: lensCenter, diameter: 82))
ctx.fillPath()

// Small detail on the right shoulder (AF-assist lamp), the family's cut-in dot.
ctx.addPath(circle(center: CGPoint(x: 380, y: 230), diameter: 26))
ctx.fillPath()

// Write the master (sRGB, no alpha).
let image = ctx.makeImage()!
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Could not write \(outPath)") }

// Pixel check (style guide §6). Coordinates are in image pixels, top-left origin.
let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
func hex(_ x: Int, _ y: Int) -> String {
    let i = (y * size + x) * 4
    return String(format: "#%02X%02X%02X", pixels[i], pixels[i + 1], pixels[i + 2])
}
let checks = [("top-left", hex(0, 0), "#009AD6"),
              ("bottom-right", hex(size - 1, size - 1), "#006CA5"),
              ("mark", hex(2 * 130, 2 * 300), "#FAF8F4"),
              ("lens glass", hex(2 * 256, 2 * 292), "#009AD6")]
var ok = true
for (name, got, want) in checks {
    print("\(name): \(got) (expected \(want))\(got == want ? "" : "  ✗")")
    ok = ok && got == want
}
print(ok ? "Pixel check passed → \(outPath)" : "Pixel check FAILED")
exit(ok ? 0 : 1)
