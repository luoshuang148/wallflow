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

需要个人媒体或账号的测试通过 [下方的集成测试环境变量](#集成测试环境变量) 启用。默认集会跳过这些场景；不要为获得全绿而删除断言或隐瞒跳过项。

退出测试使用 FFmpeg 生成红蓝两段静音视频并检验指定时间帧，系统壁纸安装边界由测试替换。实际桌面播放器测试仍会创建窗口，应先正常退出真实应用并使用静音样本，避免影响正在使用的桌面。

CI 使用 GitHub 的 `macos-15` runner，执行默认测试、Release 构建与签名检查，并保留 ZIP 构建产物。CI 产物用于检查，不会自动发布或公证应用。Runner 标签和架构定义见 [GitHub 官方文档](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

发布流程见 [RELEASING.md](RELEASING.md)，现有验证边界见 [KNOWN_ISSUES.md](KNOWN_ISSUES.md)。

## 构建路径

需要 macOS 14+ 和支持 Swift 6 的 Xcode 工具链。

```bash
git clone https://github.com/luoshuang148/wallflow.git
cd wallflow
./build.sh
open dist/WallFlow.app
```

构建脚本将应用在临时目录中完成本地签名，再输出到 `dist/WallFlow.app`。此签名适合本地构建，不包含 Developer ID 公证；其他机器、Intel Mac 和所有多屏/电源场景尚未完整验证。

可用环境变量指定构建目录和应用输出路径：

```bash
WALLFLOW_BUILD_DIR=/tmp/wallflow-build \
WALLFLOW_APP_DIR="$PWD/dist/WallFlow.app" \
./build.sh
```

源码目录名、Swift 模块名、Bundle Identifier 和设置目录沿用初版名称，以兼容已有安装。

## 集成测试环境变量

```bash
swift test
```

默认运行不依赖个人壁纸和账号的测试；缺少样本/工具时，相应媒体、桌面播放、分页样本和登录下载测试会跳过。

可通过环境变量启用本机集成测试。不要提交样本视频、Steam 会话或账号文件。

| 变量 | 用途 |
| --- | --- |
| `WALLPAPER_FOLDER` | 完整视频壁纸文件夹 |
| `WALLPAPER_SAMPLE` | 原生解码样本视频 |
| `CONVERSION_WEBM_FOLDER` | WebM 壁纸转换样本 |
| `STEAM_HTML_FIXTURES` | 本地订阅页面解析样本目录 |
| `STEAM_TEST_TOOL` | SteamCMD 可执行文件路径 |
| `STEAM_TEST_ACCOUNT_FILE` | 已登录测试账号名的本地文件 |

现有媒体回归样本约定为 3840×2160、约 16.67 秒。桌面集成测试需要可用的 macOS 图形会话，并会短暂创建播放器窗口；建议使用无音轨的视频副本。转换测试还需要 FFmpeg。没有这些环境时，基础测试仍可运行。

CI 在 macOS 上运行默认测试、Release 构建和签名检查，并提供临时构建产物。需要个人账号或媒体的测试跳过不代表这些路径已通过验证。代码地图见本文开头。
