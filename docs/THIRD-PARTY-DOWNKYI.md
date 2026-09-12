# 第三方伴随工具：B站视频下载工具 DownKyi

README §5.2 将 [DownKyi](https://github.com/leiurayer/downkyi)（MIT，C#/.NET WPF）列为推荐的"隐写外壳下载工具"。历史便携版发行包（v1.3.8.x 及以前）曾在包内附带一份 `B站视频下载工具-DownKyi-1.6.1/`（含 `aria2_COPYING.txt`、`FFmpeg_LICENSE.txt` 等许可证文件）。

## 现状与规则

- DownKyi **不是构建输入**：不被 git 跟踪，不在 `SteganographierGUI.spec` / `.iss` / CI 的任何环节出现。历史上它是打包者在发布前手工塞进 stage 目录的，这正是 RELEASING.md 所禁止的"本地目录当构建输入"模式。
- 因此自 v1.3.10 起（CI 全自动产物），官方包**不再包含** DownKyi。这是有意为之，不是回归。
- 本机使用约定：DownKyi 作为独立便携工具维护（如 `<tools-root>\downkyi-1.6.1\`），需要时把下载的外壳视频放入安装目录的 `cover_video\`。程序运行不依赖 DownKyi 存在于任何位置。
- 若未来决定恢复随包分发，必须先把它正式纳入构建链（例如 `scripts/fetch-thirdparty.ps1` 固定版本 + SHA256 校验，产物拷入 stage），并保留上游 LICENSE/许可证文件；禁止再走手工塞目录的老路。
