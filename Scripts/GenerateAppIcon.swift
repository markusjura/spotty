import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Generates Spotty's macOS app icon and menu bar image from one vector glyph: a highlighter
// resting on a bold ink band, with the band cut back around the nib. The icon puts the glyph in
// white on Shotty's system-blue rounded square. The menu bar image is the same glyph as a template,
// sized and weighted like Shotty's menu bar viewfinder. Every size is drawn directly at its pixel
// dimensions, so small sizes stay crisp and the output is deterministic.
// Run: swift Scripts/GenerateAppIcon.swift Spotty/Assets.xcassets

let assets = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Spotty/Assets.xcassets", isDirectory: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// The glyph on Apple's 1024-point icon grid, y pointing down. It fills the same 452-point square
/// as Shotty's viewfinder (a 396-point frame plus its stroke), so both icons have the same padding.
struct Glyph {
    let barrel: CGPath
    let nib: CGPath
    let band: (CGPoint, CGPoint)
    let stroke: CGFloat
    let gap: CGFloat

    static let box = CGRect(x: 286, y: 286, width: 452, height: 452)

    /// `gap` is how far the band is cut back around the marker.
    init(stroke: CGFloat, gap: CGFloat) {
        self.stroke = stroke
        self.gap = gap
        // A chisel marker pointing down in local units, tilted 40° clockwise. Every corner is
        // rounded so the outline stays clean at menu bar sizes.
        let tilt = CGAffineTransform(rotationAngle: 40 * .pi / 180)
        let barrel = Self.rounded([(-104, -380, 40), (104, -380, 40), (104, -150, 70), (56, -40, 22), (-56, -40, 22), (-104, -150, 70)], tilt)
        // The chisel's long side faces left, so after the tilt its cut lies flat on the band.
        let nib = Self.rounded([(-46, 44, 10), (46, 44, 10), (46, 88, 18), (-46, 148, 14)], tilt)

        // Scale so the barrel's top edge and the band's bottom edge span the box height. The band
        // is 1.5 strokes thick and its top touches the nib.
        let top = barrel.boundingBoxOfPath.minY, tip = nib.boundingBoxOfPath.maxY
        let scale = (Self.box.height - 2 * stroke) / (tip - top)
        let marker = barrel.boundingBoxOfPath.insetBy(dx: -stroke / 2 / scale, dy: 0).union(nib.boundingBoxOfPath)
        var place = CGAffineTransform(translationX: Self.box.midX - marker.midX * scale, y: Self.box.minY + stroke / 2 - top * scale)
            .scaledBy(x: scale, y: scale)
        self.barrel = barrel.copy(using: &place)!
        self.nib = nib.copy(using: &place)!
        // The band spans the full box width with round caps, centered under the marker.
        let bandY = tip * scale + place.ty + 0.75 * stroke, inset = 0.75 * stroke
        band = (CGPoint(x: Self.box.minX + inset, y: bandY), CGPoint(x: Self.box.maxX - inset, y: bandY))
    }

    /// A closed polygon with each corner rounded by its radius, then transformed.
    private static func rounded(_ corners: [(CGFloat, CGFloat, CGFloat)], _ transform: CGAffineTransform) -> CGPath {
        let points = corners.map { CGPoint(x: $0.0, y: $0.1) }
        let path = CGMutablePath()
        let last = points[points.count - 1]
        path.move(to: CGPoint(x: (last.x + points[0].x) / 2, y: (last.y + points[0].y) / 2))
        for (index, corner) in corners.enumerated() {
            path.addArc(tangent1End: points[index], tangent2End: points[(index + 1) % points.count], radius: corner.2)
        }
        path.closeSubpath()
        return path.copy(using: [transform])!
    }

    /// Draws the glyph in `color`. The band is cut back by a gap around the marker, so the two
    /// shapes read separately in a single color, the way SF Symbols separates overlapping layers.
    func draw(in context: CGContext, color: CGColor) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        context.setLineWidth(1.5 * stroke)
        context.move(to: band.0)
        context.addLine(to: band.1)
        context.strokePath()

        context.setBlendMode(.clear)
        context.setLineWidth(stroke + 2 * gap)
        context.addPath(barrel)
        context.strokePath()
        context.setLineWidth(2 * gap)
        context.addPath(nib)
        context.drawPath(using: .fillStroke)

        context.setBlendMode(.normal)
        context.setLineWidth(stroke)
        context.addPath(barrel)
        context.strokePath()
        context.addPath(nib)
        context.fillPath()

        context.endTransparencyLayer()
        context.restoreGState()
    }
}

/// Renders a square PNG of `pixels`, with `draw` working on the 1024-point grid scaled to fit.
func png(pixels: Int, draw: (CGContext, CGFloat) -> Void) throws -> Data {
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .high
    draw(context, scale)
    guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return data as Data
}

/// Flips the 1024-point grid so the glyph's y-down coordinates draw upright.
func flip(_ context: CGContext) {
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
}

/// Shotty's icon body: an 824-point rounded square in system blue with a soft shadow.
func drawIcon(in context: CGContext, scale: CGFloat) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    // Core Graphics shadows use device pixels rather than the transformed drawing grid.
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: CGColor(gray: 0, alpha: 0.28))
    context.addPath(shape)
    context.setFillColor(CGColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // A gentle vertical gradient in the system blue family.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 0.22, green: 0.6, blue: 1, alpha: 1),
        CGColor(srgbRed: 0, green: 0.42, blue: 0.93, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
    context.restoreGState()

    // The glyph uses Shotty's 56-point viewfinder stroke.
    flip(context)
    Glyph(stroke: 56, gap: 20).draw(in: context, color: CGColor(gray: 1, alpha: 1))
}

/// Writes PNGs and a Contents.json into an asset catalog folder.
func write(_ folder: String, images: [(name: String, data: Data, entry: [String: String])], properties: [String: Any] = [:]) throws {
    let url = assets.appendingPathComponent(folder, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    for image in images { try image.data.write(to: url.appendingPathComponent(image.name)) }
    var contents: [String: Any] = ["images": images.map { $0.entry.merging(["filename": $0.name]) { $1 } },
                                   "info": ["author": "xcode", "version": 1]]
    if !properties.isEmpty { contents["properties"] = properties }
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: url.appendingPathComponent("Contents.json"))
    print("Wrote \(images.count) images to \(url.path)")
}

var icons: [(name: String, data: Data, entry: [String: String])] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        icons.append((name, try png(pixels: size * scale, draw: drawIcon), ["idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"]))
    }
}
try write("AppIcon.appiconset", images: icons)

// The menu bar image is a 16-point template whose glyph spans 14 points, about the size of
// Shotty's 14-point medium viewfinder, with the box edges on whole pixels at 1x and 2x. The
// 43-point stroke matches that symbol's weight and makes the band exactly 4 pixels thick at 2x.
// The gap is wider than the icon's so it stays a clean 1.5-pixel cut instead of a gray smudge.
var menu: [(name: String, data: Data, entry: [String: String])] = []
for scale in [1, 2] {
    let name = "MenuBarIcon\(scale == 2 ? "@2x" : "").png"
    let data = try png(pixels: 16 * scale) { context, _ in
        let zoom = 14 / 16 * 1024 / Glyph.box.width
        context.translateBy(x: 512, y: 512)
        context.scaleBy(x: zoom, y: -zoom)
        context.translateBy(x: -512, y: -512)
        Glyph(stroke: 43, gap: 25).draw(in: context, color: CGColor(gray: 0, alpha: 1))
    }
    menu.append((name, data, ["idiom": "mac", "scale": "\(scale)x"]))
}
try write("MenuBarIcon.imageset", images: menu, properties: ["template-rendering-intent": "template"])
