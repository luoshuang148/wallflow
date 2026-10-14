# 已知问题与验证边界

以下适用于 0.7.1。已知问题与尚未验证的环境分开记录，避免将基础测试通过等同于全部集成场景通过。

## 已知问题

- 可选集成测试 `PolicyRuntimeTests.testOcclusionPausesOnlyCoveredDisplayAndRespectsGlobalPause` 曾出现两个断言失败，且已在初始 `e83a208` 基线复现。默认测试未提供媒体环境时会跳过此用例；0.7.1 本次发布未重新运行这一可选场景。遮挡策略的多屏边界仍需进一步验证。
- `SubscriptionBrowser` 和订阅测试存在 `Any?` 到 `Any` 的编译警告。

## 平台与行为边界

- 发布包仅提供 Apple Silicon / arm64，要求 macOS 14+。Intel 真机、其他设备和全部多屏/电源组合尚未完整验证。
- 应用使用本地 ad-hoc 签名，没有 Developer ID 公证，首次打开可能被 macOS 阻止。
- 正常退出只保存各显示器当前 Space 的静态壁纸；其他 Space 保持原系统壁纸。强制结束进程不能执行保存。
- 重开恢复设置与动态播放，不承诺退出时间点的精确续播。
- 旧的 `ExitWallpapers/` 图片可能仍被其他 Space 使用，因此不会自动清理。
- Steam 网页结构、SteamCMD 登录与作品访问权限受外部服务影响；网页登录不等于下载会话已登录。
- 仅支持视频项目。原生解码受 AVFoundation 支持范围限制；转码依赖可用的 FFmpeg，并可能损失画质。

## 发布验证

2026-10-14 的本机默认测试执行 113 项，跳过 31 项，失败 0 项。跳过项依赖媒体样本、工具或账号环境；这不代表全部可选集成测试通过。准确的 CI 结果与跳过项以 [Actions 日志](https://github.com/luoshuang148/wallflow/actions) 为准。

报告新问题时，请附版本、系统、芯片、显示器数量及复现步骤，并对日志脱敏。

## English

These notes primarily cover the published 0.7.1 release. Known failures and untested environments are listed separately.

### Known issues

- The optional occlusion integration test `PolicyRuntimeTests.testOcclusionPausesOnlyCoveredDisplayAndRespectsGlobalPause` previously failed two assertions, also reproduced at the initial `e83a208` baseline. It is skipped without media fixtures and was not rerun for 0.7.1. Multi-display occlusion behavior needs further validation.
- `SubscriptionBrowser` and its tests produce `Any?` to `Any` compiler warnings.

### Platform and behavior limits

- Prebuilt downloads require macOS 14+ and Apple Silicon. Intel, other devices, and all display/power combinations have not been fully tested.
- The app is ad-hoc signed without Developer ID signing or notarization; macOS may block first launch.
- Normal exit saves still frames only for the current Space on each display. Force-quitting cannot save frames, and relaunch does not promise the exact previous playback position.
- Old `ExitWallpapers/` images are retained because other Spaces may still use them.
- Steam web structure, SteamCMD login, and access permissions depend on external services. Web login does not log into SteamCMD.
- Only video projects are supported. Native playback depends on AVFoundation codec support; optional FFmpeg conversion may reduce quality.

### Validation record

The local default suite recorded for the 0.7.1 release on 2026-10-14 ran 113 tests, skipped 31, and failed none. Skips require media, tools, or account sessions and do not establish that optional integrations work. Check [Actions logs](https://github.com/luoshuang148/wallflow/actions) for current CI results.

Report new issues with the app version, macOS version, chip, display count, and reproduction steps. Sanitize logs before posting.
