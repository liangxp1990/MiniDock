import Foundation

/// 授权层（开源版）：所有功能免费，无任何限制。
/// 未来官网付费版在本仓库之外分叉时，以真实的许可证校验替换本文件即可，
/// UI 层无需改动。
@MainActor
enum License {
    /// 预留的功能枚举（官网付费版用）：自定义图片封面 / 双色渐变底板
    enum Feature: String, CaseIterable {
        case customImageCover = "自定义图片封面"
        case gradientPlate = "双色渐变底板"
    }

    static func badgeVisible(for feature: Feature) -> Bool { false }
}
