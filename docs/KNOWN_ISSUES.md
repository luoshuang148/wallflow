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
