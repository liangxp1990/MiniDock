// 生成 MiniDock 应用自身图标：玻璃底板 + 2×2 彩色色块
// 用法: swift Scripts/gen-icon.swift <输出.png>
import AppKit

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "appicon.png"
let canvas = 1024.0

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write("无法创建画布\n".data(using: .utf8)!)
    exit(1)
}
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
let plate = bounds.insetBy(dx: canvas * 0.06, dy: canvas * 0.06)
let corner = plate.width * 0.219

// 玻璃底板 + 阴影
let platePath = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.shadowBlurRadius = 48
shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
shadow.set()
NSColor.white.withAlphaComponent(0.66).setFill()
platePath.fill()
NSGraphicsContext.current?.restoreGraphicsState()

NSGradient(
    colors: [NSColor.white.withAlphaComponent(0.72), NSColor.white.withAlphaComponent(0.50)]
)?.draw(in: platePath, angle: -90)

NSColor.white.withAlphaComponent(0.65).setStroke()
platePath.lineWidth = 3
platePath.stroke()

// 2×2 色块
let tiles: [(NSColor, NSColor)] = [
    (NSColor(srgbRed: 0.24, green: 0.86, blue: 0.52, alpha: 1), NSColor(srgbRed: 0.10, green: 0.69, blue: 0.35, alpha: 1)),
    (NSColor(srgbRed: 0.27, green: 0.66, blue: 1.00, alpha: 1), NSColor(srgbRed: 0.09, green: 0.41, blue: 0.86, alpha: 1)),
    (NSColor(srgbRed: 1.00, green: 0.84, blue: 0.04, alpha: 1), NSColor(srgbRed: 0.94, green: 0.63, blue: 0.10, alpha: 1)),
    (NSColor(srgbRed: 1.00, green: 0.42, blue: 0.42, alpha: 1), NSColor(srgbRed: 0.87, green: 0.19, blue: 0.23, alpha: 1)),
]

let content = plate.insetBy(dx: plate.width * 0.10, dy: plate.height * 0.10)
let gap = plate.width * 0.05
let cell = (content.width - gap) / 2

for index in 0..<4 {
    let column = CGFloat(index % 2)
    let row = CGFloat(index / 2)
    let rect = CGRect(
        x: content.minX + column * (cell + gap),
        y: content.maxY - row * (cell + gap) - cell,
        width: cell, height: cell
    )
    let tilePath = NSBezierPath(roundedRect: rect, xRadius: cell * 0.22, yRadius: cell * 0.22)
    NSGradient(colors: [tiles[index].0, tiles[index].1])?.draw(in: tilePath, angle: -90)

    // 白色几何符号
    NSColor.white.setFill()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = cell * 0.17
    switch index {
    case 0:
        NSBezierPath(ovalIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )).fill()
    case 1:
        NSBezierPath(
            roundedRect: CGRect(
                x: center.x - radius * 0.9, y: center.y - radius * 0.9,
                width: radius * 1.8, height: radius * 1.8
            ),
            xRadius: radius * 0.35, yRadius: radius * 0.35
        ).fill()
    case 2:
        let triangle = NSBezierPath()
        triangle.move(to: CGPoint(x: center.x, y: center.y + radius))
        triangle.line(to: CGPoint(x: center.x - radius, y: center.y - radius))
        triangle.line(to: CGPoint(x: center.x + radius, y: center.y - radius))
        triangle.close()
        triangle.fill()
    default:
        let diamond = NSBezierPath()
        diamond.move(to: CGPoint(x: center.x, y: center.y + radius))
        diamond.line(to: CGPoint(x: center.x - radius, y: center.y))
        diamond.line(to: CGPoint(x: center.x, y: center.y - radius))
        diamond.line(to: CGPoint(x: center.x + radius, y: center.y))
        diamond.close()
        diamond.fill()
    }
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG 编码失败\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
print("icon written: \(output)")
