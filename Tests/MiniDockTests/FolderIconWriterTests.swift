import Testing
import AppKit
@testable import MiniDock

/// 手工资源分叉写入器：结构约束（icns 容器 magic、fork 头字段、map 长度）
@Suite struct FolderIconWriterTests {
    @Test func icnsContainerIsValid() throws {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor.systemPurple.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
        image.unlockFocus()

        let icns = try #require(FolderIconWriter.buildIcns(image))
        #expect(String(bytes: icns.prefix(4), encoding: .ascii) == "icns")
        let total = (Int(icns[4]) << 24) | (Int(icns[5]) << 16) | (Int(icns[6]) << 8) | Int(icns[7])
        #expect(total == icns.count, "长度字段应等于容器总长")
        // 至少含一个 PNG 表项（magic 后紧跟尺寸表项）
        #expect(icns.count > 100)
    }

    @Test func forkHeaderFieldsAreConsistent() {
        let payload = Data(repeating: 0xAB, count: 1234)
        let fork = FolderIconWriter.buildFork(icns: payload)
        func be32(_ o: Int) -> Int {
            (Int(fork[o]) << 24) | (Int(fork[o+1]) << 16) | (Int(fork[o+2]) << 8) | Int(fork[o+3])
        }
        #expect(fork.count == 256 + 4 + 1234 + 50)
        #expect(be32(0) == 256, "数据段固定从 256 开始")
        #expect(be32(4) == 256 + 4 + 1234, "map 偏移 = 256 + 数据段")
        #expect(be32(8) == 4 + 1234, "数据段长度")
        #expect(be32(12) == 50, "map 长度 50")
        // 数据段开头是 4 字节长度 + icns 原文
        #expect(fork[256] == 0 && fork[257] == 0 && fork[258] == 4 && fork[259] == 210)
        #expect(fork[260] == 0xAB)
    }
}
