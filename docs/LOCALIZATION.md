# 中英本地化验证

公开 0.9.3 包尚不含本轮本地化。源码通过 key/格式检查、编译和非 GUI Bundle 查找验证不等于全流程 UI 已验收。按维护者要求，本轮保留当前播放状态、跳过实机录制和视觉截图，没有生成虚构的英文截图。

```sh
python3 scripts/check_localization.py
./build.sh
```

主应用和内嵌 WallFlowPlayer 都复制 zh-Hans.lproj、en.lproj，开发语言为 zh-Hans。系统语言为英文时匹配英文，不支持的语言回退中文。用户自带的壁纸标题、显示器名称和错误中的文件名不会被翻译。

后续在可停止旧后台播放器的测试会话中验证（先保留当前配置）：

```sh
open -n "$PWD/dist/WallFlow.app" --args -AppleLanguages '(en)'
# 完全退出该测试会话，再测试中文；不要让两个管理端争用同一个后台播放器。
open -n "$PWD/dist/WallFlow.app" --args -AppleLanguages '(zh-Hans)'
```

逐项检查：主窗口/空状态、导入与失败提示、显示器分配、设置和播放策略、创意工坊、菜单栏、弹窗、通知与辅助功能标签；检查英文长文本截断、中文原文、参数显示与取消/退出流程。先确认截图只含原创合成壁纸，隐藏用户库、路径和账号；未经实机验收不要对外宣称完整英文体验。
