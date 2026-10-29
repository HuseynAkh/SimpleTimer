import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Centered watch geometry shared by light, dark and tinted appearances.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
for appearance in ["Any", "Dark", "Tinted"] {
    let dark = appearance != "Any"
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    func shade(_ value: CGFloat) -> CGColor { CGColor(red: value, green: value, blue: value, alpha: 1) }
    let ink = shade(dark ? 0.97 : 0.07)
    context.setFillColor(shade(dark ? 0.045 : 0.985))
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // Two concentric, perfectly centered rings form the watch case.
    context.setStrokeColor(shade(dark ? 0.48 : 0.57))
    context.setLineWidth(10)
    context.strokeEllipse(in: CGRect(x: 192, y: 192, width: 640, height: 640))
    context.setStrokeColor(ink)
    context.setLineWidth(26)
    context.strokeEllipse(in: CGRect(x: 224, y: 224, width: 576, height: 576))

    // Four equal hour indices preserve the dial's vertical/horizontal balance.
    context.setLineWidth(18)
    for (x1, y1, x2, y2) in [(512.0, 738.0, 512.0, 708.0), (512, 286, 512, 316), (286, 512, 316, 512), (738, 512, 708, 512)] {
        context.move(to: CGPoint(x: x1, y: y1))
        context.addLine(to: CGPoint(x: x2, y: y2))
        context.strokePath()
    }

    // Balanced 10:10 hands and a short counterweight.
    context.setLineWidth(30)
    context.move(to: CGPoint(x: 385, y: 601))
    context.addLine(to: CGPoint(x: 512, y: 512))
    context.addLine(to: CGPoint(x: 639, y: 601))
    context.strokePath()
    context.setLineWidth(14)
    context.move(to: CGPoint(x: 512, y: 512))
    context.addLine(to: CGPoint(x: 512, y: 462))
    context.strokePath()
    context.setFillColor(ink)
    context.fillEllipse(in: CGRect(x: 493, y: 493, width: 38, height: 38))

    let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("AppIcon-\(appearance).png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}
