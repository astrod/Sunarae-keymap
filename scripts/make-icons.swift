import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let set = output.appendingPathComponent("Sunarae.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

func draw(size: Int, menu: Bool) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let s = CGFloat(size)
    if !menu {
        NSColor(calibratedRed: 0.15, green: 0.39, blue: 0.30, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88),
                     xRadius: s * 0.18, yRadius: s * 0.18).fill()
    }
    let text: NSString = "순"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s * (menu ? 0.81 : 0.57), weight: .semibold),
        .foregroundColor: menu ? NSColor.black : NSColor.white
    ]
    let bounds = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (s - bounds.width) / 2, y: (s - bounds.height) / 2), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try draw(size: size * scale, menu: false).representation(using: .png, properties: [:])!
            .write(to: set.appendingPathComponent(name))
    }
}
let menu = NSImage(size: NSSize(width: 16, height: 16))
for size in [16, 32] {
    let representation = draw(size: size, menu: true)
    representation.size = NSSize(width: 16, height: 16)
    menu.addRepresentation(representation)
}
try menu.tiffRepresentation!.write(to: output.appendingPathComponent("MenuIcon.tiff"))
