# 开发说明

WallFlow 使用 Swift Package Manager；Swift 6 工具链、Swift 5 语言模式，最低 macOS 14。无外部 Swift 包依赖。

## 代码地图

| 位置 | 职责 |
| --- | --- |
| `Sources/VideoWallpaperApp/` | SwiftUI 管理界面、菜单栏、系统通知与退出流程 |
| `Sources/VideoWallpaperApp/VideoPreviewSurface.swift` | AVPlayerLayer、首帧状态和窗口可见性 |
| `Sources/WallpaperCore/` | 项目解析、安全路径、搜索、持久化模型和媒体验证 |
| `Sources/WallpaperRuntime/LibraryModel.swift` | 库状态、导入与应用、设置、运行策略和退出快照 |
| `Sources/WallpaperRuntime/WallpaperEngine.swift` | 各屏桌面窗口、播放器、遮挡、音频与退出冻结 |
| `Sources/WallpaperRuntime/VideoPreviewModel.swift` | 独立静音预览的生命周期 |
| `Sources/WallpaperRuntime/StaticWallpaperKeeper.swift` | 导出视频帧并交给 macOS 静态壁纸接口 |
| `Sources/WallpaperRuntime/WorkshopModel.swift` | 下载、订阅候选、导入与本机扫描 |
| `Sources/WallpaperRuntime/SubscriptionBrowser.swift` | WebKit 订阅读取与分页 |
| `Sources/WallpaperRuntime/SteamRunner.swift` | SteamCMD 子进程、取消、超时与输出 |
| `Sources/WallpaperRuntime/VideoConverter.swift` | FFmpeg 发现、转换与缓存 |
| `Tests/WallpaperCoreTests/` | 解析、状态、搜索和库功能测试 |
| `Tests/WallpaperRuntimeTests/` | 播放、预览、退出、工坊和策略测试 |
| `Resources/Info.plist` | 应用版本、Bundle 身份和最低系统版本 |
| `build.sh` | Release 构建、临时目录 ad-hoc 签名和输出 |

## 本地验证

```bash
swift test
./build.sh
codesign --verify --deep --strict dist/WallFlow.app
```

同一 SwiftPM scratch 目录的构建和测试需按顺序运行。若同步文件夹附加了 Finder 元数据，可将应用用 `ditto --norsrc --noextattr` 复制到干净临时目录后检查签名。

需要个人媒体或账号的测试通过 [README 中的环境变量](../README.md#测试) 启用。默认集会跳过这些场景；不要为获得全绿而删除断言或隐瞒跳过项。

退出测试使用 FFmpeg 生成红蓝两段静音视频并检验指定时间帧，系统壁纸安装边界由测试替换。实际桌面播放器测试仍会创建窗口，应先正常退出真实应用并使用静音样本，避免影响正在使用的桌面。

CI 使用 GitHub 的 `macos-15` runner，执行默认测试、Release 构建与签名检查，并保留 ZIP 构建产物。CI 产物用于检查，不会自动发布或公证应用。Runner 标签和架构定义见 [GitHub 官方文档](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

发布流程见 [RELEASING.md](RELEASING.md)，现有验证边界见 [KNOWN_ISSUES.md](KNOWN_ISSUES.md)。
