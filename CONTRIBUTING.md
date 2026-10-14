# 参与 WallFlow / Contributing

欢迎中文或英文 Issue 和 Pull Request。项目目前专注 macOS 视频壁纸；Scene、网页和程序壁纸属于不同的实现范围，大规模功能请先通过 Issue 讨论。

你可以从修正文档、补充英文说明、报告复现步骤或验证自己的 Mac 配置开始。讨论请保持友善，聚焦具体问题，尊重不同经验的参与者。

## 报告问题

使用 [问题模板](https://github.com/luoshuang148/wallflow/issues/new/choose)，提供应用版本、macOS 版本、芯片、显示器数量、复现步骤、预期与实际结果。播放或转换问题请注明容器/编码、尺寸、声音选项及可选工具版本。

请使用有权分享的最小样本。不要上传 Steam 密码、验证码、Cookie、登录令牌、`ssfn*`、Steam 配置、完整状态文件或个人壁纸。截图和日志中的账号名、用户名、媒体路径请先脱敏。漏洞按 [SECURITY.md](SECURITY.md) 私下报告。

## 开发流程

1. 在 macOS 14+ 上安装支持 Swift 6 的 Xcode 工具链，Fork 并克隆仓库。
2. 为改动建立独立分支，保持 Pull Request 聚焦一个问题。
3. 代码改动运行 `swift test` 和 `./build.sh`；纯文档改动检查链接与渲染即可。涉及媒体或桌面行为时，按 [开发指南](docs/DEVELOPMENT.md#集成测试环境变量) 启用相关集成测试，并注明跳过项。
4. 提交 PR，说明具体问题、修改后的行为和实际验证结果；界面改动可附脱敏截图。

SwiftPM 使用 Swift 5 语言模式。沿用现有代码风格，不为文档或低风险文案调整添加只重复实现的测试；行为变化应提供能复现问题的回归测试。

## 兼容性约束

- 保留 `VideoWallpaper` 模块、Bundle 身份和数据目录的兼容性；修改持久化模型时考虑已有数据。
- 不重置用户偏好，不改写导入项目的 `project.json`，不删除源视频。
- 预览保持静音并独立于桌面播放；音频偏好应保存，多屏只允许一处出声。
- 导入路径必须位于源项目目录内；取消和过期请求不能安装新播放器。
- 退出静态画面的历史文件可能被其他 Space 引用，不可按“旧文件”直接清理。

维护者可按 [发布清单](docs/RELEASING.md) 发版。贡献者请仅提交自己有权授权的代码、文档或资源；第三方工具与壁纸不得混入仓库。

## English

Contributions are welcome in Chinese or English. Documentation fixes, translations, reproducible bug reports, and testing on your Mac are useful even without writing code. Keep discussions respectful and focused on the issue.

The project currently focuses on macOS video wallpapers. Scene, web, and application wallpapers require different implementations. Discuss substantial features in an Issue before starting work.

### Report a problem

Use the [issue forms](https://github.com/luoshuang148/wallflow/issues/new/choose). Include the app version, macOS version, chip, display count, reproduction steps, and expected and actual behavior. For playback or conversion, include container/codec, dimensions, audio settings, and relevant tool versions.

Only share minimal samples you have permission to distribute. Remove accounts, usernames, and personal paths from screenshots and logs. Never upload passwords, verification codes, cookies, tokens, `ssfn*`, Steam configuration, complete state files, or private wallpapers. Report vulnerabilities privately under [SECURITY.md](SECURITY.md).

### Development workflow

1. Use a Swift 6-capable Xcode toolchain on macOS 14+. Fork and clone the repository.
2. Create a branch and keep the PR focused on one problem.
3. For code changes, run `swift test` and `./build.sh`. For media or desktop behavior, run relevant integrations from the [development guide](docs/DEVELOPMENT.md#集成测试环境变量) and list skipped cases. Documentation-only changes need link and rendering checks rather than an app build.
4. Explain the problem, resulting behavior, and actual validation in the PR. Include sanitized screenshots for UI changes.

SwiftPM uses Swift 5 language mode. Follow existing code style. Behavior changes should include a regression test that reproduces the problem. Avoid tests that merely repeat the implementation for low-risk text edits.

### Compatibility

- Preserve module names, bundle identity, and existing data paths. Consider migration when changing stored models.
- Do not reset preferences, rewrite imported `project.json`, or delete source media.
- Keep previews silent and independent of desktop playback; persist audio settings and allow sound from only one display.
- Keep imported media paths inside the project directory; canceled or stale requests must not install players.
- Do not automatically delete old exit frames that other Spaces may still use.

See the [release checklist](docs/RELEASING.md) for distribution. Submit only code, documentation, and assets you are entitled to contribute. Do not bundle third-party tools or wallpapers. The repository has no selected open-source license yet; see the README for its current status.
