import AppKit

/// 马赛克网格的布局结论：列数、行数与实际绘制的图标数。
/// 强制 2×2 时多于 4 个的应用会被裁掉（不溢出底板）。
struct MosaicLayout: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let shown: Int
}

/// 按 CoverStyle 合成分类封面图标。
/// 支持底板：玻璃白/玻璃深/纯色/双色渐变/自定义图片；布局自动或强制 2×2/3×3；
/// 参数：圆角、间距、图标占格；可选数量角标。视觉规格见 design/ 下的设计稿。
@MainActor
enum MosaicIconGenerator {
    /// 由应用总数与布局偏好推导网格：列数 → 显示数裁到 columns×columns → 行数。
    /// 布局计算独立于绘制，便于单元测试与后续调整。
    nonisolated static func layout(for count: Int, style: CoverStyle) -> MosaicLayout {
        let columns: Int
        switch style.layout {
        case .auto: columns = count <= 4 ? 2 : 3
        case .two: columns = 2
        case .three: columns = 3
        }
        let shown = min(count, columns * columns)
        let rows = shown == 0 ? 0 : (shown + columns - 1) / columns
        return MosaicLayout(columns: columns, rows: rows, shown: shown)
    }

    static func generate(
        forAppPaths paths: [String],
        style: CoverStyle,
        customImage: NSImage? = nil,
        canvasSize: CGFloat = 1024
    ) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize), pixelsHigh: Int(canvasSize),
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            return NSImage(size: NSSize(width: canvasSize, height: canvasSize))
        }
        rep.size = NSSize(width: canvasSize, height: canvasSize)

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        drawCover(
            in: CGRect(origin: .zero, size: CGSize(width: canvasSize, height: canvasSize)),
            paths: paths,
            style: style,
            customImage: customImage
        )
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    static func drawCover(
        in bounds: CGRect,
        paths: [String],
        style: CoverStyle,
        customImage: NSImage? = nil
    ) {
        let unit = bounds.width / 1024
        // 四周留 6% 给外阴影
        let plate = bounds.insetBy(dx: bounds.width * 0.06, dy: bounds.height * 0.06)
        let corner = plate.width * min(max(style.cornerRadiusPercent, 4), 34) / 100
        let platePath = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)

        // 底板 + 外阴影
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -18 * unit)
        shadow.shadowBlurRadius = 48 * unit
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.set()
        NSColor.white.withAlphaComponent(0.5).setFill()
        platePath.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        // 底板内容
        switch style.plate {
        case .glassLight:
            gradient([alpha(NSColor.white, 0.72), alpha(NSColor.white, 0.50)], in: platePath)
        case .glassDark:
            gradient([
                alpha(NSColor(srgbRed: 70 / 255, green: 70 / 255, blue: 76 / 255, alpha: 1), 0.92),
                alpha(NSColor(srgbRed: 44 / 255, green: 44 / 255, blue: 48 / 255, alpha: 1), 0.80),
            ], in: platePath)
        case .solid(let hex):
            let base = NSColor.fromHex(hex)
            gradient([alpha(base, 0.92), alpha(base, 0.78)], in: platePath)
        case .gradient(let topHex, let bottomHex):
            gradient([
                alpha(NSColor.fromHex(topHex), 0.96),
                alpha(NSColor.fromHex(bottomHex), 0.88),
            ], in: platePath)
        case .image:
            if let image = customImage {
                drawImagePlate(image, in: plate, corner: corner)
            } else {
                gradient([alpha(NSColor.white, 0.72), alpha(NSColor.white, 0.50)], in: platePath)
            }
        }

        // 描边 + 内高光
        NSColor.white.withAlphaComponent(0.65).setStroke()
        platePath.lineWidth = 3 * unit
        platePath.stroke()
        let inner = NSBezierPath(
            roundedRect: plate.insetBy(dx: 3 * unit, dy: 3 * unit),
            xRadius: max(corner - 3 * unit, 1), yRadius: max(corner - 3 * unit, 1)
        )
        NSColor.white.withAlphaComponent(0.35).setStroke()
        inner.lineWidth = 2 * unit
        inner.stroke()

        if style.plate == .image {
            if style.overlayMiniIcons, !paths.isEmpty {
                drawMiniIconStrip(paths, in: plate, unit: unit)
            }
        } else if paths.isEmpty {
            drawEmptyGlyph(in: plate)
        } else {
            drawMosaic(paths, in: plate, style: style)
        }

        if style.showCountBadge, !paths.isEmpty {
            drawCountBadge(paths.count, in: plate, unit: unit)
        }
    }

    // MARK: - 组成部分

    private static func drawImagePlate(_ image: NSImage, in plate: CGRect, corner: CGFloat) {
        NSGraphicsContext.current?.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)
        clip.addClip()
        // 等比裁切填充（aspect-fill）
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            NSGraphicsContext.current?.restoreGraphicsState()
            return
        }
        let scale = max(plate.width / size.width, plate.height / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(
            x: plate.midX - drawSize.width / 2,
            y: plate.midY - drawSize.height / 2
        )
        image.draw(
            in: CGRect(origin: origin, size: drawSize),
            from: .zero, operation: .sourceOver, fraction: 1
        )
        // 顶部轻渐变以保持玻璃质感
        gradient([
            NSColor.white.withAlphaComponent(0.12),
            NSColor.black.withAlphaComponent(0.0),
        ], in: NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner))
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private static func drawMiniIconStrip(_ paths: [String], in plate: CGRect, unit: CGFloat) {
        let shown = Array(paths.prefix(4))
        let side = plate.width * 0.15
        let gap = side * 0.18
        let capsuleWidth = CGFloat(shown.count) * side + CGFloat(shown.count - 1) * gap + side * 0.5
        let capsuleHeight = side * 1.5
        let capsuleRect = CGRect(
            x: plate.midX - capsuleWidth / 2,
            y: plate.minY + plate.width * 0.07,
            width: capsuleWidth, height: capsuleHeight
        )
        let capsule = NSBezierPath(
            roundedRect: capsuleRect, xRadius: capsuleHeight / 2, yRadius: capsuleHeight / 2
        )
        NSColor.black.withAlphaComponent(0.35).setFill()
        capsule.fill()
        NSColor.white.withAlphaComponent(0.4).setStroke()
        capsule.lineWidth = unit * 2
        capsule.stroke()

        var x = capsuleRect.minX + side * 0.25
        let y = capsuleRect.midY - side / 2
        for path in shown {
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: side, height: side)
            icon.draw(in: CGRect(x: x, y: y, width: side, height: side))
            x += side + gap
        }
    }

    private static func drawMosaic(_ paths: [String], in plate: CGRect, style: CoverStyle) {
        let grid = layout(for: paths.count, style: style)
        let shown = Array(paths.prefix(grid.shown))
        let columns = grid.columns
        let content = plate.insetBy(dx: plate.width * 0.10, dy: plate.height * 0.10)
        let gap = plate.width * min(max(style.gapPercent, 1), 16) / 100
        let cell = (content.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let iconSide = cell * min(max(style.iconScalePercent, 40), 100) / 100

        // 整块垂直居中；不满一行的尾行水平居中，避免“偏左上、右下留空”
        let blockHeight = CGFloat(grid.rows) * cell + CGFloat(grid.rows - 1) * gap
        let blockTopY = content.midY + blockHeight / 2

        for (index, path) in shown.enumerated() {
            let row = index / columns
            let itemsInRow = min(columns, shown.count - row * columns)
            let rowWidth = CGFloat(itemsInRow) * cell + CGFloat(itemsInRow - 1) * gap
            let rowLeftX = content.midX - rowWidth / 2
            let column = index % columns
            let cellX = rowLeftX + CGFloat(column) * (cell + gap)
            let cellYTop = blockTopY - CGFloat(row) * (cell + gap)
            let cellRect = CGRect(x: cellX, y: cellYTop - cell, width: cell, height: cell)
            let iconRect = CGRect(
                x: cellRect.midX - iconSide / 2,
                y: cellRect.midY - iconSide / 2,
                width: iconSide, height: iconSide
            )
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = iconRect.size
            NSGraphicsContext.current?.saveGraphicsState()
            let iconShadow = NSShadow()
            iconShadow.shadowOffset = NSSize(width: 0, height: -4 / 1024 * plate.width)
            iconShadow.shadowBlurRadius = 12 / 1024 * plate.width
            iconShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            iconShadow.set()
            icon.draw(in: iconRect)
            NSGraphicsContext.current?.restoreGraphicsState()
        }
    }

    private static func drawCountBadge(_ count: Int, in plate: CGRect, unit: CGFloat) {
        let fontSize = plate.width * 0.10
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = "\(count)" as NSString
        let textSize = text.size(withAttributes: attributes)
        let padding = fontSize * 0.42
        let capsuleHeight = fontSize * 1.55
        let capsuleWidth = textSize.width + padding * 2
        let inset = plate.width * 0.055
        let rect = CGRect(
            x: plate.maxX - inset - capsuleWidth,
            y: plate.minY + inset,
            width: capsuleWidth, height: capsuleHeight
        )
        let capsule = NSBezierPath(
            roundedRect: rect, xRadius: capsuleHeight / 2, yRadius: capsuleHeight / 2
        )
        NSColor(srgbRed: 0.08, green: 0.08, blue: 0.10, alpha: 0.88).setFill()
        capsule.fill()
        NSColor.white.withAlphaComponent(0.45).setStroke()
        capsule.lineWidth = 2 * unit
        capsule.stroke()
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width, height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }

    private static func drawEmptyGlyph(in plate: CGRect) {
        let config = NSImage.SymbolConfiguration(
            paletteColors: [NSColor(calibratedWhite: 0.55, alpha: 1)]
        )
        let base = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        guard let symbol = base?.withSymbolConfiguration(config) else { return }
        let side = plate.width * 0.42
        symbol.draw(in: CGRect(
            x: plate.midX - side / 2, y: plate.midY - side / 2,
            width: side, height: side
        ))
    }

    private static func gradient(_ colors: [NSColor], in path: NSBezierPath) {
        NSGradient(colors: colors)?.draw(in: path, angle: -90)
    }

    private static func alpha(_ color: NSColor, _ value: CGFloat) -> NSColor {
        color.withAlphaComponent(value)
    }
}

extension NSColor {
    /// 解析 #RGB / #RRGGBB 十六进制色
    static func fromHex(_ hex: String) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
