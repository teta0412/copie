import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Copie/Assets.xcassets", isDirectory: true)
let appIcon = assets.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let menuIcon = assets.appendingPathComponent("MenuBarIcon.imageset", isDirectory: true)
try FileManager.default.createDirectory(at: appIcon, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: menuIcon, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func render(size: Int, template: Bool, to url: URL) {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    if template {
        let black = color(0, 0, 0)
        let board = roundedRect(CGRect(x: 238, y: 155, width: 548, height: 665), radius: 82)
        context.addPath(board)
        context.setStrokeColor(black)
        context.setLineWidth(78)
        context.strokePath()

        let clip = roundedRect(CGRect(x: 390, y: 746, width: 244, height: 114), radius: 48)
        context.addPath(clip)
        context.setFillColor(black)
        context.fillPath()

        let pie = CGRect(x: 328, y: 282, width: 368, height: 368)
        context.addEllipse(in: pie)
        context.setStrokeColor(black)
        context.setLineWidth(72)
        context.strokePath()

        context.setLineWidth(62)
        context.setLineCap(.round)
        for x in [438.0, 548.0] {
            context.move(to: CGPoint(x: x, y: 392))
            context.addLine(to: CGPoint(x: x + 44, y: 545))
            context.strokePath()
        }
    } else {
        let background = roundedRect(CGRect(x: 30, y: 30, width: 964, height: 964), radius: 218)
        context.addPath(background)
        context.clip()
        let gradient = CGGradient(colorsSpace: space, colors: [color(0.19, 0.10, 0.24), color(0.39, 0.16, 0.34)] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 140, y: 900), end: CGPoint(x: 850, y: 100),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.resetClip()

        let backSheet = roundedRect(CGRect(x: 250, y: 150, width: 590, height: 660), radius: 78)
        context.addPath(backSheet)
        context.setFillColor(color(0.76, 0.44, 0.35))
        context.fillPath()

        let board = roundedRect(CGRect(x: 185, y: 178, width: 610, height: 664), radius: 82)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -20), blur: 28, color: color(0.08, 0.02, 0.10, 0.32))
        context.addPath(board)
        context.setFillColor(color(1, 0.94, 0.83))
        context.fillPath()
        context.restoreGState()

        let clip = roundedRect(CGRect(x: 387, y: 770, width: 206, height: 113), radius: 48)
        context.addPath(clip)
        context.setFillColor(color(0.82, 0.48, 0.28))
        context.fillPath()
        context.addEllipse(in: CGRect(x: 476, y: 830, width: 28, height: 28))
        context.setFillColor(color(0.35, 0.17, 0.22))
        context.fillPath()

        let crust = CGRect(x: 281, y: 280, width: 418, height: 418)
        let filling = CGRect(x: 320, y: 319, width: 340, height: 340)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8), blur: 14, color: color(0.38, 0.18, 0.14, 0.28))
        for index in 0..<24 {
            let angle = CGFloat(index) * .pi / 12
            let center = CGPoint(x: 490 + cos(angle) * 203, y: 489 + sin(angle) * 203)
            context.addEllipse(in: CGRect(x: center.x - 27, y: center.y - 27, width: 54, height: 54))
        }
        context.addEllipse(in: crust)
        context.setFillColor(color(0.93, 0.65, 0.32))
        context.fillPath()
        context.restoreGState()
        context.addEllipse(in: filling)
        context.setFillColor(color(0.67, 0.23, 0.27))
        context.fillPath()

        context.saveGState()
        context.addEllipse(in: filling)
        context.clip()
        context.setStrokeColor(color(1, 0.78, 0.43))
        context.setLineWidth(29)
        for offset in [-165.0, -55.0, 55.0, 165.0] {
            context.move(to: CGPoint(x: 265, y: 490 + offset - 225))
            context.addLine(to: CGPoint(x: 715, y: 490 + offset + 225))
            context.strokePath()
            context.move(to: CGPoint(x: 265, y: 490 + offset + 225))
            context.addLine(to: CGPoint(x: 715, y: 490 + offset - 225))
            context.strokePath()
        }
        context.restoreGState()
        context.addEllipse(in: CGRect(x: 309, y: 308, width: 362, height: 362))
        context.setStrokeColor(color(1, 0.76, 0.40))
        context.setLineWidth(42)
        context.strokePath()
    }

    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}

let appSizes = [16, 32, 64, 128, 256, 512, 1024]
for size in appSizes {
    render(size: size, template: false, to: appIcon.appendingPathComponent("icon-\(size).png"))
}
for size in [18, 36] {
    render(size: size, template: true, to: menuIcon.appendingPathComponent("menu-\(size).png"))
}

let iconEntries: [[String: String]] = [
    ["size": "16x16", "scale": "1x", "filename": "icon-16.png"],
    ["size": "16x16", "scale": "2x", "filename": "icon-32.png"],
    ["size": "32x32", "scale": "1x", "filename": "icon-32.png"],
    ["size": "32x32", "scale": "2x", "filename": "icon-64.png"],
    ["size": "128x128", "scale": "1x", "filename": "icon-128.png"],
    ["size": "128x128", "scale": "2x", "filename": "icon-256.png"],
    ["size": "256x256", "scale": "1x", "filename": "icon-256.png"],
    ["size": "256x256", "scale": "2x", "filename": "icon-512.png"],
    ["size": "512x512", "scale": "1x", "filename": "icon-512.png"],
    ["size": "512x512", "scale": "2x", "filename": "icon-1024.png"]
].map { $0.merging(["idiom": "mac"]) { current, _ in current } }
let menuEntries: [[String: String]] = [
    ["idiom": "universal", "scale": "1x", "filename": "menu-18.png"],
    ["idiom": "universal", "scale": "2x", "filename": "menu-36.png"]
]
func writeJSON(_ entries: [[String: String]], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}
try writeJSON(iconEntries, to: appIcon.appendingPathComponent("Contents.json"))
try writeJSON(menuEntries, to: menuIcon.appendingPathComponent("Contents.json"))
