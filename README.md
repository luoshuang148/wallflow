<img src="docs/assets/icon.png" width="96" height="96" alt="WallFlow 图标">

# WallFlow

[English](README.en.md) · [下载](https://github.com/luoshuang148/wallflow/releases/latest) · [更新日志](CHANGELOG.md) · [问题反馈](https://github.com/luoshuang148/wallflow/issues/new/choose)

[![macOS CI](https://github.com/luoshuang148/wallflow/actions/workflows/ci.yml/badge.svg)](https://github.com/luoshuang148/wallflow/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Apple Silicon](https://img.shields.io/badge/download-Apple%20Silicon-black)

macOS 视频动态壁纸应用。支持导入 Wallpaper Engine 视频壁纸文件夹，以及通过 Steam 创意工坊下载和导入账号订阅的视频作品。

当前开发版本：**0.9.0（build 19）**；已公开的安装包为 **0.7.1**。主要在 Apple Silicon Mac 上开发和验证，使用 SwiftUI、AppKit 和 AVFoundation。

## 功能

- 视频循环播放，多显示器独立设置，铺满或完整显示。
- `⌘Q` 退出管理程序后，由独立后台播放器继续播放；设置提供“停止壁纸并完全退出”，完整退出时保留静态画面。
- 选中壁纸后静音动态预览，保持视频原比例；窗口隐藏、遮挡或打开设置时释放预览播放器。
- 名称/编号搜索、重命名、收藏、分组和排序。
- 顺序/随机轮播、日夜切换、指定目标屏幕。
- 全局播放声音/静音；多屏时仅一块正在播放的屏幕出声。
- 桌面遮挡、电池供电、低电量模式、锁屏和休眠暂停。
- 按应用运行/前台状态静音、暂停或停止并释放播放资源。
- 登录启动，以及 Steam 创意工坊链接下载、订阅读取和本机扫描。
- 内嵌官方创意工坊网页，搜索、筛选和浏览作品详情；点击“下载此作品”下载并导入视频壁纸。
- 非 MP4 或不可原生播放的视频使用 FFmpeg 转换，保留原文件。

仅支持视频壁纸，不支持 Wallpaper Engine 的 Scene、网页或程序壁纸。WallFlow 是独立应用。

## 下载安装

1. 从 [最新 Release](https://github.com/luoshuang148/wallflow/releases/latest) 下载 `WallFlow-0.7.1-macOS-arm64.zip`，适用于 macOS 14+ 的 Apple Silicon Mac。
2. 解压后将 `WallFlow.app` 拖入“应用程序”，再打开应用。
3. 若 macOS 阻止打开，请按 [Apple 的说明](https://support.apple.com/zh-cn/102445)，在尝试打开后到 **系统设置 → 隐私与安全性 → 仍要打开** 为该应用确认例外。
4. 导入自己的完整视频壁纸文件夹即可使用；下载创意工坊作品或转换视频时，再配置下方的可选工具。

发布包使用本地 ad-hoc 签名，**尚无 Developer ID 签名和 Apple 公证**。Intel Mac 暂无预编译下载，源码构建也尚未在 Intel 真机完整验证。发布包不包含壁纸、SteamCMD 或 FFmpeg。

Release 附带 `SHA256SUMS.txt`。把它和 ZIP 放在同一目录，可核对下载完整性：

```bash
shasum -a 256 -c SHA256SUMS.txt
```

更新时先使用“停止壁纸并完全退出”（0.8.x 及更早版本使用菜单栏退出），确认后台已停止后再替换应用。保留原媒体文件和本地数据目录，已有壁纸库、屏幕分配和声音偏好会继续使用。

## 构建

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

## 使用

1. 在 **创意工坊 → 其他来源 → 导入壁纸文件夹…** 选择包含 `project.json` 和视频的完整文件夹。
   也可打开 **创意工坊 → 浏览工坊…**，使用官方搜索、分类和排序选择作品，在详情页点击 **下载此作品**；默认筛选视频，非视频作品不会启用下载。
2. 选中壁纸，设置 **应用到**、**画面显示** 和 **声音**，点击应用。声音选项即时生效并保存。
3. 右键壁纸或点击标题旁的铅笔可改名；星标可收藏。
4. **设置 → 壁纸库与自动播放** 管理分组、轮播、应用规则和登录启动。
5. **设置 → 性能与电源** 管理自动暂停策略。

关闭窗口或按 `⌘Q` 退出管理程序后，独立的 `WallFlowPlayer` 继续播放，菜单栏图标可重新打开管理窗口。设置底部和菜单栏均提供“停止壁纸并完全退出”。应用引用原视频文件；从库中移除记录不会删除原文件。自定义名称保存在本机，不修改源 `project.json`。

选择“停止壁纸并完全退出”会把当前视频帧保存为 macOS 静态壁纸，沿用各屏幕的画面显示设置；应用规则已释放播放器时使用已应用视频的首帧。完整退出后不再播放视频或声音；管理程序 `⌘Q` 退出不会中断播放、声音、轮播或自动暂停规则。再次打开管理程序连接已有后台，不重置播放进度；完整退出后重新启动恢复保存的屏幕分配、声音和暂停设置。强制结束进程无法执行退出保存。macOS 的公开接口只更新各屏幕当前所在的桌面空间（Space），其他桌面空间的系统壁纸保持原状。

轮播和登录启动默认关闭，应用规则默认为空。登录启动使用 macOS 登录项服务，可能需要把应用放入“应用程序”文件夹并在系统设置中批准。

## 可选工具

### FFmpeg

原生可播放的 MP4 不依赖 FFmpeg。其他格式会转换为 H.264/MP4 与可选 AAC 音轨；重新编码可能有画质损失，并占用缓存空间。

支持在应用旁放置 `MediaTools/ffmpeg`，或使用 Homebrew 安装：

```bash
brew install ffmpeg
```

也会查找 `/opt/homebrew/bin/ffmpeg` 和 `/usr/local/bin/ffmpeg`。仓库不包含 FFmpeg 或转换缓存。

### SteamCMD

创意工坊下载需要 [Valve 官方 SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD) 和拥有 Wallpaper Engine 的 Steam 账号。仓库不包含 SteamCMD、Steam 登录数据或壁纸资源。

可在创意工坊页面选择 `steamcmd`，或使用以下目录结构：

```text
dist/
├── WallFlow.app
└── SteamTools/
    └── MacOS/
        └── steamcmd
```

Mac 版 SteamCMD 为 Intel 程序，Apple Silicon 上可能需要 Rosetta。工具在独立目录中更新，不写入应用签名包。

在创意工坊页面填写下载账号并登录；支持粘贴作品链接或编号下载，或读取自己的订阅列表后选择视频批量导入。Steam 网页与 SteamCMD 是独立登录会话。订阅同步不会订阅、取消订阅或删除本地壁纸。

“通过链接下载…”和“导入本机已下载”位于 **其他来源** 菜单，主页面优先提供“浏览工坊”和“读取 Steam 订阅”。

“浏览工坊”和“读取 Steam 订阅”共享应用内的网页会话；已在其中登录时通常无需重新登录。只有 SteamCMD 已登录而网页尚未登录时，网页仍需单独登录。浏览范围以 Steam 对当前账号开放的内容为准，无法访问删除、隐藏或无权限的作品。下载会重新校验作品类型，完成后导入库，不自动改变桌面壁纸。

## 测试

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
| `STEAM_BROWSER_LIVE_TEST=1` | 访问真实公开工坊页面与视频详情，验证内嵌 WebKit 和作品信息；不下载作品 |

现有媒体回归样本约定为 3840×2160、约 16.67 秒。桌面集成测试需要可用的 macOS 图形会话，并会短暂创建播放器窗口；建议使用无音轨的视频副本。转换测试还需要 FFmpeg。没有这些环境时，基础测试仍可运行。

CI 在 macOS 上运行默认测试、Release 构建和签名检查，并提供临时构建产物。需要个人账号或媒体的测试跳过不代表这些路径已通过验证。开发地图见 [开发说明](docs/DEVELOPMENT.md)。

## 本地数据

设置位于 `~/Library/Application Support/VideoWallpaper/`：

- `state.json`：壁纸库、屏幕分配、名称、播放和自动化设置。
- `workshop.json`：普通下载账号名和工具路径。
- `ConvertedVideos/`：转换视频缓存，正在使用时需保留。
- `Runtime/`：后台单实例锁、当前会话状态和完整退出请求；不包含账号凭据。
- `ExitWallpapers/`：退出后交给 macOS 显示的静态画面。历史图片可能仍被其他桌面空间引用，因此会保留；可手动清理确定不再使用的图片。

网页登录会话由 WebKit 管理，下载登录由 SteamCMD 管理。应用不提取或复制密码、Cookie 和登录令牌到源码仓库。

`.gitignore` 排除了构建产物、视频、工具目录、本机设置、Steam 会话、日志及常见凭据文件。

## 常见问题

- **为什么没有 Scene 壁纸？** 当前只实现视频壁纸，不解析 Wallpaper Engine 的 Scene、网页或程序项目，也不承诺兼容全部视频编码。
- **关闭窗口或按 ⌘Q 后为什么仍在播放？** 独立后台播放器继续运行；在设置或菜单栏选择“停止壁纸并完全退出”可停止播放，并保存静态画面。
- **退出后所有 Space 都会更新吗？** 只更新每块屏幕当前所在的 Space。强制结束应用不会执行保存；重开应用恢复设置，不保证从退出的准确时间点续播。
- **网页已登录，为什么下载还要求登录？** Steam 网页和 SteamCMD 使用独立会话；创意工坊下载需要有权限访问作品的账号。
- **转换为什么失败？** 检查 FFmpeg 是否安装、源文件是否仍可读取，以及缓存目录剩余空间。原生可播放的 MP4 无需转换。

其他验证边界见 [已知问题](docs/KNOWN_ISSUES.md)。

## 参与项目

欢迎提交可复现的问题、文档改进和 Pull Request。开始前请阅读 [贡献指南](CONTRIBUTING.md)；涉及账号会话、目录逃逸或其他漏洞时，请按 [安全报告说明](SECURITY.md) 私下报告。

WallFlow 与 Valve、Steam、Wallpaper Engine 无隶属或官方合作关系。第三方工具及壁纸资源遵循各自的许可与作者授权。

## 许可证

当前仓库尚未添加许可证，许可方案待项目作者确定。
