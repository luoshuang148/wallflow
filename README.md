# WallFlow

macOS 视频动态壁纸应用。支持导入 Wallpaper Engine 视频壁纸文件夹，以及通过 Steam 创意工坊下载和导入账号订阅的视频作品。

当前版本：**0.7.1**。主要在 Apple Silicon Mac 上开发和验证，使用 SwiftUI、AppKit 和 AVFoundation。

## 功能

- 视频循环播放，多显示器独立设置，铺满或完整显示。
- 正常退出时保留各屏幕的视频画面为系统静态壁纸，再次启动恢复动态播放和原有设置。
- 选中壁纸后静音动态预览，保持视频原比例；窗口隐藏、遮挡或打开设置时释放预览播放器。
- 名称/编号搜索、重命名、收藏、分组和排序。
- 顺序/随机轮播、日夜切换、指定目标屏幕。
- 全局播放声音/静音；多屏时仅一块正在播放的屏幕出声。
- 桌面遮挡、电池供电、低电量模式、锁屏和休眠暂停。
- 按应用运行/前台状态静音、暂停或停止并释放播放资源。
- 登录启动，以及 Steam 创意工坊链接下载、订阅读取和本机扫描。
- 非 MP4 或不可原生播放的视频使用 FFmpeg 转换，保留原文件。

仅支持视频壁纸，不支持 Wallpaper Engine 的 Scene、网页或程序壁纸。WallFlow 是独立应用。

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

1. 在 **创意工坊 → 导入壁纸文件夹** 选择包含 `project.json` 和视频的完整文件夹。
2. 选中壁纸，设置 **应用到**、**画面显示** 和 **声音**，点击应用。声音选项即时生效并保存。
3. 右键壁纸或点击标题旁的铅笔可改名；星标可收藏。
4. **设置 → 壁纸库与自动播放** 管理分组、轮播、应用规则和登录启动。
5. **设置 → 性能与电源** 管理自动暂停策略。

关闭窗口后继续播放，通过菜单栏图标打开管理窗口或退出。应用引用原视频文件；从库中移除记录不会删除原文件。自定义名称保存在本机，不修改源 `project.json`。

正常退出会把当前视频帧保存为 macOS 静态壁纸，沿用各屏幕的画面显示设置；应用规则已释放播放器时使用已应用视频的首帧。退出后不再播放视频或声音，重新启动恢复保存的屏幕分配、声音和暂停设置。强制结束进程无法执行退出保存。macOS 的公开接口只更新各屏幕当前所在的桌面空间（Space），其他桌面空间的系统壁纸保持原状。

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

现有媒体回归样本约定为 3840×2160、约 16.67 秒。桌面集成测试需要可用的 macOS 图形会话，并会短暂创建播放器窗口；建议使用无音轨的视频副本。转换测试还需要 FFmpeg。没有这些环境时，基础测试仍可运行。

## 本地数据

设置位于 `~/Library/Application Support/VideoWallpaper/`：

- `state.json`：壁纸库、屏幕分配、名称、播放和自动化设置。
- `workshop.json`：普通下载账号名和工具路径。
- `ConvertedVideos/`：转换视频缓存，正在使用时需保留。
- `ExitWallpapers/`：退出后交给 macOS 显示的静态画面。历史图片可能仍被其他桌面空间引用，因此会保留；可手动清理确定不再使用的图片。

网页登录会话由 WebKit 管理，下载登录由 SteamCMD 管理。应用不提取或复制密码、Cookie 和登录令牌到源码仓库。

`.gitignore` 排除了构建产物、视频、工具目录、本机设置、Steam 会话、日志及常见凭据文件。
