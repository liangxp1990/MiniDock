import AppKit
import Darwin

/// 手工写文件夹自定义图标：icns 容器 → Icon\r 资源分叉（com.apple.ResourceFork
/// xattr）+ FinderInfo 标志位。
///
/// 不用 NSWorkspace.setIcon：它内部走 IconServices XPC，在应用进程内存在
/// 时序 guard 间歇触发 os_log_fault 直接崩溃（实测全天 21 次），绕开后完全确定。
enum FolderIconWriter {
    /// 资源分叉 map 段模板（单 icns 资源、id 0x0320，实测与 NSWorkspace 写出的结构一致；
    /// 前 16 字节为残留句柄值，Resource Manager 不读取）
    private static let mapTemplate: [UInt8] = [
        0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xE5, 0x5E,
        0x00, 0x00, 0xE4, 0x5E, 0x00, 0x00, 0x00, 0x32,
        0x03, 0x00, 0x00, 0x00, 0x0B, 0x00, 0x00, 0x00,
        0x00, 0x1C, 0x00, 0x32, 0x00, 0x00, 0x69, 0x63,
        0x6E, 0x73, 0x00, 0x00, 0x00, 0x0A, 0xBF, 0xB9,
        0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x00, 0x00,
    ]

    /// icns 输出的像素规格（全部走 PNG 编码的现代表项）
    private static let sizes: [(type: String, pixels: Int)] = [
        ("ic10", 1024), ("ic09", 512), ("ic08", 256), ("ic07", 128), ("icp5", 32), ("icp4", 16),
    ]

    private static func be32(_ v: Int) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static func pngData(from image: NSImage, pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// 把 NSImage 打包成多尺寸 icns 容器
    static func buildIcns(_ image: NSImage) -> Data? {
        var body = Data()
        for entry in sizes {
            guard let png = pngData(from: image, pixels: entry.pixels) else { continue }
            body.append(Data(entry.type.utf8))
            body.append(Data(be32(png.count + 8)))
            body.append(png)
        }
        guard !body.isEmpty else { return nil }
        var icns = Data("icns".utf8)
        icns.append(Data(be32(body.count + 8)))
        icns.append(body)
        return icns
    }

    /// icns → 单资源资源分叉字节流（256B 头 + [长度][icns] 数据段 + 50B map）
    static func buildFork(icns: Data) -> Data {
        let dataSection = Data(be32(icns.count)) + icns
        let mapOffset = 256 + dataSection.count
        var fork = Data(repeating: 0, count: 256)
        fork.replaceSubrange(0..<4, with: Data(be32(256)))            // 数据段偏移
        fork.replaceSubrange(4..<8, with: Data(be32(mapOffset)))      // map 偏移
        fork.replaceSubrange(8..<12, with: Data(be32(dataSection.count)))
        fork.replaceSubrange(12..<16, with: Data(be32(mapTemplate.count)))
        fork += dataSection
        fork += Data(mapTemplate)
        return fork
    }

    private static func setXattr(_ path: String, _ name: String, _ bytes: [UInt8]) -> Int32 {
        path.withCString { p in
            name.withCString { n in
                bytes.withUnsafeBufferPointer { buf in
                    setxattr(p, n, buf.baseAddress, buf.count, 0, 0)
                }
            }
        }
    }

    private static func finderInfo(withFlags flags: UInt16) -> [UInt8] {
        var info = [UInt8](repeating: 0, count: 32)
        info[8] = UInt8((flags >> 8) & 0xFF)
        info[9] = UInt8(flags & 0xFF)
        return info
    }

    /// 写入自定义图标：Icon\r 空文件 + 资源分叉 + FinderInfo 标志，并触碰目录时间戳
    static func apply(_ image: NSImage, toFolder folderPath: String) throws {
        guard let icns = buildIcns(image) else {
            throw NSError(domain: "MiniDock.FolderIconWriter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "icns 打包失败"])
        }
        let fm = FileManager.default
        let iconPath = folderPath + "/Icon\r"

        if !fm.fileExists(atPath: iconPath) {
            guard fm.createFile(atPath: iconPath, contents: Data()) else {
                throw NSError(domain: "MiniDock.FolderIconWriter", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "无法创建 Icon\r 文件"])
            }
        }
        guard setXattr(iconPath, "com.apple.ResourceFork", [UInt8](buildFork(icns: icns))) == 0 else {
            throw NSError(domain: "MiniDock.FolderIconWriter", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "写入资源分叉失败"])
        }
        _ = setXattr(iconPath, "com.apple.FinderInfo", finderInfo(withFlags: 0x4000 | 0x0400))
        _ = setXattr(folderPath, "com.apple.FinderInfo", finderInfo(withFlags: 0x0400))
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: folderPath)
    }
}
