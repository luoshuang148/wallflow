# 发布清单

公开 Release 只分发 Wallnamic、自有说明文档及仓库许可。不打包个人壁纸、账号文件、Steam 会话、转换缓存、本机日志、SteamCMD 或 FFmpeg。第三方工具由用户从官方渠道获取。

## 1. 准备版本

- 确认工作区干净，发布提交已进入远端 `main`。
- 更新 `Resources/Info.plist` 的版本号和 build，并同步中英文 README、使用指南和 `CHANGELOG.md`，确保下载文件名与实际附件一致。
- 运行 `./build.sh`；查看 CI 结果，记录失败项。
- 对需要媒体、账号或多屏环境的验证单独记录；不要声称未运行的场景已通过。

## 2. 干净打包

以下命令在 macOS 仓库根目录执行，版本号必须与 Info.plist 一致：

```bash
(
set -euo pipefail
release_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
release_arch=$(uname -m)
release_stage=$(mktemp -d /private/tmp/wallnamic-release.XXXXXX)
release_output="$PWD/dist/releases/$release_version"
release_name="Wallnamic-$release_version"
release_zip="Wallnamic-$release_version-macOS-$release_arch.zip"
release_dmg="Wallnamic-$release_version-macOS-$release_arch.dmg"
mkdir -p "$release_stage/$release_name" "$release_output"
WALLNAMIC_APP_DIR="$release_stage/$release_name/Wallnamic.app" ./build.sh
cp README.md "$release_stage/$release_name/README.md"
cp README.en.md "$release_stage/$release_name/README.en.md"
cp -R docs "$release_stage/$release_name/docs"
cp CHANGELOG.md CONTRIBUTING.md SECURITY.md SUPPORT.md "$release_stage/$release_name/"
if [ -f LICENSE ]; then cp LICENSE "$release_stage/$release_name/LICENSE"; fi
codesign --verify --deep --strict "$release_stage/$release_name/Wallnamic.app"
ditto -c -k --norsrc --noextattr --keepParent \
  "$release_stage/$release_name" "$release_output/$release_zip"
dmg_root=$(mktemp -d /private/tmp/wallnamic-dmg.XXXXXX)
cp -R "$release_stage/$release_name/Wallnamic.app" "$dmg_root/Wallnamic.app"
ln -s /Applications "$dmg_root/Applications"
hdiutil create -volname "Wallnamic" -srcfolder "$dmg_root" -ov -format UDZO \
  -imagekey zlib-level=9 "$release_output/$release_dmg"
rm -rf "$dmg_root"
(cd "$release_output" && shasum -a 256 "$release_zip" "$release_dmg" > SHA256SUMS.txt)
)
```

只删除本次创建的临时目录，保留产物。不要使用运行中的工具目录作为打包来源。

## 3. 独立验证

- 用 `ditto -x -k` 解压 ZIP 到另一个干净临时目录，运行严格签名检查；用 `hdiutil attach` 挂载 DMG，确认含 `Wallnamic.app` 与 `Applications` 软链后 `hdiutil detach`。
- 从解压应用读取 Info.plist，确认版本、build、最低系统版本；用 `file` 确认可执行文件架构。
- 检查 ZIP 目录无 `config`、`logs`、`userdata`、Steam 会话、媒体、`__MACOSX` 或 `._*`。
- 在产物目录运行 `shasum -a 256 -c SHA256SUMS.txt`（覆盖 ZIP 与 DMG）。
- 正常退出和重启的真机验证需保留用户数据；不要把强制结束进程当作正常退出验证。

## 4. 发布到 GitHub

为经过验证且已推送的提交创建 `v<版本>` 标签，先创建包含 **DMG、ZIP 与 `SHA256SUMS.txt`** 的草稿 Release。说明包含新增行为、安装与更新方法（优先写 DMG 拖拽安装，ZIP 作为备选）、系统/芯片要求、签名状态、工具依赖、已知问题和实际测试结果。

核对草稿的目标提交与附件后再公开；避免复用或移动已经公开的版本标签。0.7.0 与 0.6.4 没有历史 GitHub 二进制 Release，不为它们补挂新版安装包。
