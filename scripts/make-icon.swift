// Renders the 1024×1024 app icon master. Usage: swift scripts/make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

func glow(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32, _ alpha: CGFloat) {
    ctx.drawRadialGradient(
        gradient([color(hex, alpha), color(hex, 0)], [0, 1]),
        startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: []
    )
}

// macOS icon grid: 824pt body centred on a 1024 canvas, leaving room for the drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.45))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x0B0D1F))
ctx.fillPath()
ctx.restoreGState()

// Body: deep night gradient with aurora glows.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0x2A2F7A), color(0x151538), color(0x07080F)], [0, 0.55, 1]),
    start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: []
)
glow(CGPoint(x: 260, y: 760), 420, 0x8B5CF6, 0.55)
glow(CGPoint(x: 800, y: 720), 380, 0x22D3EE, 0.35)
glow(CGPoint(x: 560, y: 250), 420, 0xEC4899, 0.30)

// Top sheen.
ctx.drawLinearGradient(
    gradient([color(0xFFFFFF, 0.14), color(0xFFFFFF, 0)], [0, 1]),
    start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: []
)
ctx.restoreGState()

// Hairline rim.
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 183, cornerHeight: 183, transform: nil))
ctx.setStrokeColor(color(0xFFFFFF, 0.12))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// The island: a black pill with a live activity inside.
let pill = CGRect(x: 512 - 300, y: 512 - 92, width: 600, height: 184)
let pillPath = CGPath(roundedRect: pill, cornerWidth: 92, cornerHeight: 92, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: color(0xA78BFA, 0.65))
ctx.addPath(pillPath)
ctx.setFillColor(color(0x000000))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0x000000, 0.7))
ctx.addPath(pillPath)
ctx.setFillColor(color(0x000000))
ctx.fillPath()
ctx.restoreGState()

// Glassy rim on the pill.
ctx.saveGState()
ctx.addPath(pillPath)
ctx.setLineWidth(4)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0xFFFFFF, 0.38), color(0xFFFFFF, 0.06), color(0xFFFFFF, 0.16)], [0, 0.5, 1]),
    start: CGPoint(x: 512, y: pill.maxY), end: CGPoint(x: 512, y: pill.minY), options: []
)
ctx.restoreGState()

// Left: gradient "artwork" disc.
let disc = CGRect(x: pill.minX + 46, y: pill.midY - 46, width: 92, height: 92)
ctx.saveGState()
ctx.addEllipse(in: disc)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0xF472B6), color(0x8B5CF6), color(0x22D3EE)], [0, 0.5, 1]),
    start: CGPoint(x: disc.minX, y: disc.maxY), end: CGPoint(x: disc.maxX, y: disc.minY), options: []
)
ctx.restoreGState()
ctx.addEllipse(in: CGRect(x: disc.midX - 13, y: disc.midY - 13, width: 26, height: 26))
ctx.setFillColor(color(0x000000, 0.85))
ctx.fillPath()

// Right: equaliser bars.
let bars: [CGFloat] = [46, 88, 120, 72, 104, 56]
let barWidth: CGFloat = 18
let gap: CGFloat = 14
let barsWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
let barsStart = pill.maxX - 62 - barsWidth
ctx.saveGState()
let barsPath = CGMutablePath()
for (i, h) in bars.enumerated() {
    let x = barsStart + CGFloat(i) * (barWidth + gap)
    barsPath.addRoundedRect(
        in: CGRect(x: x, y: pill.midY - h / 2, width: barWidth, height: h),
        cornerWidth: barWidth / 2, cornerHeight: barWidth / 2
    )
}
ctx.addPath(barsPath)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0x22D3EE), color(0xA78BFA), color(0xF472B6)], [0, 0.5, 1]),
    start: CGPoint(x: barsStart, y: 0), end: CGPoint(x: barsStart + barsWidth, y: 0), options: []
)
ctx.restoreGState()

// Camera lens dot between the two, as on the real island.
let lens = CGRect(x: 512 - 70 - 20, y: pill.midY - 20, width: 40, height: 40)
ctx.saveGState()
ctx.addEllipse(in: lens)
ctx.clip()
ctx.drawRadialGradient(
    gradient([color(0x3B4A8C), color(0x0E1330), color(0x050608)], [0, 0.45, 1]),
    startCenter: CGPoint(x: lens.midX - 6, y: lens.midY + 6), startRadius: 0,
    endCenter: CGPoint(x: lens.midX, y: lens.midY), endRadius: 20, options: []
)
ctx.restoreGState()
ctx.addEllipse(in: CGRect(x: lens.midX - 9, y: lens.midY + 3, width: 7, height: 7))
ctx.setFillColor(color(0xFFFFFF, 0.55))
ctx.fillPath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
