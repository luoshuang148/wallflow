<img src="docs/assets/icon.png" width="96" height="96" alt="WallFlow icon">

# WallFlow

[简体中文](README.md) · [Download](https://github.com/luoshuang148/wallflow/releases/latest) · [Changelog](CHANGELOG.md) · [Report an issue](https://github.com/luoshuang148/wallflow/issues/new/choose)

[![macOS CI](https://github.com/luoshuang148/wallflow/actions/workflows/ci.yml/badge.svg)](https://github.com/luoshuang148/wallflow/actions/workflows/ci.yml)

A native macOS video wallpaper app built with SwiftUI, AppKit, and AVFoundation. Import complete Wallpaper Engine **video** wallpaper folders, download Workshop videos with SteamCMD, or browse your account's subscribed videos. The application interface is currently in Simplified Chinese.

Current development version: **0.9.1 (build 20)**; the published download remains **0.7.1**. Requires **macOS 14+**. Prebuilt downloads target **Apple Silicon (arm64)**; Intel hardware has not been fully tested.

## Features

- Loop videos with independent assignments per display and fill/fit modes.
- Menu-bar Quit and Command-Q quit management while an independent background player continues. Settings offers “停止壁纸并完全退出” (Stop wallpaper and completely quit), saving a static frame.
- Silent animated previews at the video's aspect ratio, with cover fallback and resource cleanup when the window is hidden, minimized, or fully occluded, during sleep, or while another management view is open.
- Search, local renaming, favorites, groups, sorting, sequential/random playlists, and day/night switching.
- Optional audio; only one playing display produces sound at a time.
- Pause policies for desktop occlusion, battery power, Low Power Mode, screen lock, and sleep.
- Per-application mute/pause/stop rules and optional launch at login.
- Workshop links/IDs, subscription browsing, local scanning, and FFmpeg conversion while retaining source files.
- Embedded official Workshop browsing with search, filters, sorting, and a “下载此作品” (Download this item) button on eligible video details pages.

Only video wallpapers are supported. Scene, web, and application wallpapers are outside the current scope. WallFlow is an independent application, unaffiliated with Valve, Steam, or Wallpaper Engine.

## Install

1. Download `WallFlow-0.7.1-macOS-arm64.zip` from the [latest release](https://github.com/luoshuang148/wallflow/releases/latest).
2. Extract the ZIP and move `WallFlow.app` to Applications.
3. The app is **ad-hoc signed and not notarized**. If macOS blocks it, follow [Apple's instructions](https://support.apple.com/en-us/102445): after trying to open the app, use **System Settings → Privacy & Security → Open Anyway** to confirm an exception for this app.
4. Under **创意工坊 → 其他来源** (Workshop → Other sources), select **导入壁纸文件夹…** (Import wallpaper folder) and choose a complete folder containing `project.json` and its video.
5. Choose **应用到** (Display), **画面显示** (Fill/Fit), and **声音** (Audio), then apply the wallpaper.

The release includes no wallpapers, SteamCMD, or FFmpeg. Verify the ZIP by placing it beside the release's `SHA256SUMS.txt` and running:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

To update, use “停止壁纸并完全退出” to stop the background player before replacing the app (use the menu-bar Quit action on version0.8.x and earlier). Keep your media files and application data in place.

## Optional tools

Playable MP4 files work without additional tools. For other formats, install FFmpeg (`brew install ffmpeg`), or place an executable at `MediaTools/ffmpeg` beside the app. WallFlow also checks `/opt/homebrew/bin/ffmpeg` and `/usr/local/bin/ffmpeg`. Conversion uses H.264/MP4 with an optional AAC track; it may reduce quality and uses cache space.

Workshop downloads require [Valve's SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD) and a Steam account with access to the Wallpaper Engine content. Select the SteamCMD executable in the Workshop screen or use this layout:

```text
Applications/
├── WallFlow.app
└── SteamTools/
    └── MacOS/
        └── steamcmd
```

The macOS SteamCMD tool may require Rosetta on Apple Silicon. Steam's web session and SteamCMD's download session are separate logins. Subscription browsing does not subscribe/unsubscribe or delete local wallpapers.

Since development version0.8.0, **创意工坊 → 浏览工坊…** opens the official website inside the app, initially filtered to Video. It shares the persistent web session used by subscription browsing. A SteamCMD login alone does not log into the webpage. Steam determines which items your account may view; inaccessible/deleted/private items are not guaranteed. The download button rechecks the item and imports supported videos without automatically applying a wallpaper.

Manual link downloads and importing already-downloaded local items are available under **其他来源** (Other sources). Browsing and subscription reading are the primary actions.

## Build and test

Use a Swift 6-capable Xcode toolchain on macOS 14+:

```bash
git clone https://github.com/luoshuang148/wallflow.git
cd wallflow
./build.sh
open dist/WallFlow.app
swift test
```

`WALLFLOW_BUILD_DIR` and `WALLFLOW_APP_DIR` override the build cache and app output paths. The build script ad-hoc signs in a temporary directory before copying the app to its destination.

Default tests skip cases requiring personal media, tools, or account sessions. See the [Chinese README's test variables](README.md#测试) and [development guide](docs/DEVELOPMENT.md) for integration testing. CI runs default tests and builds the app on macOS; a green result does not validate skipped integrations or all hardware combinations.

## Data and limitations

Settings remain in `~/Library/Application Support/VideoWallpaper/` for compatibility:

- `state.json`: library, assignments, names, playback preferences, and automation.
- `workshop.json`: download account name and tool paths.
- `ConvertedVideos/`: converted media cache; retain files still in use.
- `Runtime/`: the singleton lease, current-session status, and shutdown request; no account credentials.
- `ExitWallpapers/`: installed static frames; older frames may still be referenced by other Spaces.

Closing the management window, selecting menu-bar Quit, or pressing Command-Q keeps wallpapers, audio, playlists and pause policies running in the independent `WallFlowPlayer`. Reopening management connects to the same player without resetting playback. Use the complete-exit action in Settings to stop both processes and save stills for each display's **current Space only**. Force-quitting the player cannot save them. Relaunch after a complete exit restores settings without promising the exact previous playback position. Source media is referenced in place; removing a library entry does not delete it, and renaming does not modify the source `project.json`.

macOS may ask for access to protected folders containing imported wallpapers, including Downloads and Documents. Local ad-hoc re-signing may trigger a new prompt. The user controls this access; denied files cannot be restored for playback.

See [known issues](docs/KNOWN_ISSUES.md), [contribution guidelines](CONTRIBUTING.md), and the [security policy](SECURITY.md). Third-party tools and wallpaper assets retain their own licenses and author permissions.

## License

The repository does not yet include a license. The project author has not selected one.
