# 发版流程（GitHub Actions 自动发布 + Sparkle 自动更新）

## 一次性准备（已完成）

- Sparkle EdDSA 密钥对：私钥备份在 `~/.minidock-sparkle-private.edkey`（**务必再备份一份到安全位置，丢失后无法再发更新**），公钥已写入 App 的 `SUPublicEDKey`。
- GitHub 仓库 secret `SPARKLE_PRIVATE_KEY` 已配置（Settings → Secrets and variables → Actions）。
- CI 使用 `macos-26` runner + Xcode 26.6（Liquid Glass API 需要）。

## 日常发版：只需打 tag

```bash
git tag 2.4
git push origin 2.4
```

tag 以 `v*` 匹配规则触发 `.github/workflows/release.yml`，CI 自动完成：

1. 构建 `build/MiniDock.app`（复用 `Scripts/make-app.sh` 的逻辑）
2. 打包 `MiniDock-<版本>.dmg`
3. 用 secret 中的私钥对 DMG 做 EdDSA 签名
4. 生成/更新仓库根目录 `appcast.xml` 并提交回 `main` 分支
5. 创建 GitHub Release 并上传 DMG

发完后去 Actions 页确认绿色，Release 页应有新 DMG。

## 用户侧更新链路

App 内置 Sparkle 2：

- `SUFeedURL` 指向 `https://raw.githubusercontent.com/liangxp1990/MiniDock/main/appcast.xml`
- 启动后每天自动检查一次；也可菜单「MiniDock → 检查更新…（⌘U）」手动检查
- 发现新版本 → 下载 → EdDSA 验签 → 「安装并重启」→ 自动替换 App 并重启

## 注意事项

- **版本号三处一致**：`Scripts/make-app.sh` 默认版本、tag 名、appcast 中的 `sparkle:shortVersionString`。本地打包用 `./Scripts/make-app.sh release 2.4`；CI 用 tag 名。
- appcast.xml 由 CI 提交回 main，若本机同时改了 appcast 先 pull 再打 tag，避免冲突。
- 未公证（ad-hoc 签名）：Gatekeeper 首次打开仍需右键 → 打开。后续可申请 Developer ID 公证。
