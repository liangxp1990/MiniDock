import Foundation
import Sparkle

/// Sparkle 自动更新控制器（更新通道托管于 GitHub Releases 的 appcast.xml）。
/// 更新包经 EdDSA 签名校验（公钥在 Info.plist 的 SUPublicEDKey）。
final class UpdaterController: SPUStandardUpdaterController {
    init() {
        super.init(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updater.automaticallyChecksForUpdates = true
        updater.updateCheckInterval = 86_400  // 24h
        updater.automaticallyDownloadsUpdates = false
    }
}
