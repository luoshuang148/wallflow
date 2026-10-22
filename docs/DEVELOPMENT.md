# 开发说明

Wallnamic 使用 Swift Package Manager；Swift 6 工具链、Swift 5 语言模式，最低 macOS 14。无外部 Swift 包依赖。

## 代码地图

| 位置 | 职责 |
| --- | --- |
| `Sources/VideoWallpaperApp/` | SwiftUI 管理界面、菜单栏、系统通知与退出流程 |
| `Sources/VideoWallpaperApp/VideoPreviewSurface.swift` | AVPlayerLayer、首帧状态和窗口可见性 |
| `Sources/WallpaperCore/` | 项目解析、安全路径、搜索、持久化模型和媒体验证 |
| `Sources/WallFlowPlayer/App.swift` | 独立后台播放器入口、登录控制模式与完整退出 |
| `Sources/WallpaperCore/SharedStateStore.swift` | 跨进程状态合并、锁与变更通知 |
| `Sources/WallpaperRuntime/BackgroundPlayer.swift` | 单实例租约、会话状态、启动及停止请求 |
| `Sources/WallpaperRuntime/DesktopPlaybackHost.swift` | 后台模型与播放策略、系统通知 |
| `Sources/WallpaperRuntime/PlayerLoginStartup.swift` | 由播放器自身管理 macOS 登录项 |
| `Sources/WallpaperRuntime/LibraryModel.swift` | 库状态、导入与应用、设置、运行策略和退出快照 |
| `Sources/WallpaperRuntime/WallpaperEngine.swift` | 各屏桌面窗口、播放器、遮挡、音频与退出冻结 |
| `Sources/WallpaperRuntime/VideoPreviewModel.swift` | 独立静音预览的生命周期 |
| `Sources/WallpaperRuntime/StaticWallpaperKeeper.swift` | 导出视频帧并交给 macOS 静态壁纸接口 |
| `Sources/WallpaperRuntime/WorkshopModel.swift` | 下载、订阅候选、导入与本机扫描 |
| `Sources/WallpaperRuntime/SubscriptionBrowser.swift` | WebKit 订阅读取与分页 |
| `Sources/WallpaperRuntime/WorkshopBrowser.swift` | 官方工坊浏览、导航和请求代次保护的作品信息 |
| `Sources/VideoWallpaperApp/WorkshopBrowserView.swift` | 浏览窗口、当前作品下载、进度和失败原因 |
| `Sources/WallpaperRuntime/SteamRunner.swift` | SteamCMD 子进程、取消、超时与输出 |
| `Sources/WallpaperRuntime/VideoConverter.swift` | FFmpeg 发现、转换与缓存 |
| `Resources/Info.plist` | 应用版本、Bundle 身份和最低系统版本 |
| `build.sh` | Release 构建、临时目录 ad-hoc 签名和输出 |

## 本地验证

```bash
./build.sh
codesign --verify --deep --strict dist/Wallnamic.app
```

若同步文件夹附加了 Finder 元数据，可将应用用 `ditto --norsrc --noextattr` 复制到干净临时目录后检查签名。

CI 使用 GitHub 的 `macos-15` runner，执行 Release 构建与签名检查，并保留 ZIP 构建产物。CI 产物用于检查，不会自动发布或公证应用。Runner 标签和架构定义见 [GitHub 官方文档](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

发布流程见 [RELEASING.md](RELEASING.md)，现有验证边界见 [KNOWN_ISSUES.md](KNOWN_ISSUES.md)。

## 构建路径

需要 macOS 14+ 和支持 Swift 6 的 Xcode 工具链。

```bash
git clone https://github.com/luoshuang148/wallnamic.git
cd wallnamic
./build.sh
open dist/Wallnamic.app
```

构建脚本将应用在临时目录中完成本地签名，再输出到 `dist/Wallnamic.app`。此签名适合本地构建，不包含 Developer ID 公证；其他机器、Intel Mac 和所有多屏/电源场景尚未完整验证。

可用环境变量指定构建目录和应用输出路径：

```bash
WALLNAMIC_BUILD_DIR=/tmp/wallnamic-build \
WALLNAMIC_APP_DIR="$PWD/dist/Wallnamic.app" \
./build.sh
```

源码目录名、Swift 模块名、Bundle Identifier 和设置目录沿用初版名称，以兼容已有安装。

## 品牌改名与兼容性

Wallnamic 原名 WallFlow。应用显示名和输出目录已更新；`VideoWallpaper`、`WallFlowPlayer` 可执行文件、播放器内嵌路径、Bundle Identifier、本地设置目录、登录项标识与进程通信协议保持不变。无需迁移媒体或设置。构建参数优先使用 `WALLNAMIC_BUILD_DIR`、`WALLNAMIC_APP_DIR`、`WALLNAMIC_CHECK_LOCALIZATION`；旧的 `WALLFLOW_*` 参数仍可使用。
