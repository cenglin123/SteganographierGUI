# 更新日志

版本号遵循 `x.y.z` 三段式（以 VERSION 文件为准）。历史 tag 一律不可移动、不可重打。

## v1.3.10（2026-08-18，tag: v1.3.10 → 5c3be5f）

首个由 GitHub Actions 全自动构建发布的版本（portable ZIP + Inno 安装包 + SHA256SUMS.txt）。

### 新功能
- 解除隐写遇到同名文件时支持**自动重命名**（生成 `xxx (1).ext`），GUI 新增"解除隐写重名自动改名"勾选项，CLI 提供 `--auto-rename`（b95740e）。
- CLI 模式不再依赖 Tkinter，无图形库环境（服务器、精简 Python）可纯命令行使用（PR #24，eb725b6）。

### 右键菜单集成
- 安装/卸载脚本全面重写为 PowerShell（`context-menu/Install-ContextMenu.ps1` / `Uninstall-ContextMenu.ps1`），支持安装路径含空格、中文及 `!` 等特殊字符（PR #30，89e6165）。
- 修复安装路径包含 `!` 时右键菜单路径丢失的问题。

### 打包与发布
- 新增自动化发布流水线（`.github/workflows/release.yml` + `scripts/build-release.ps1` / `validate-release.ps1` / `smoke-test.ps1` / `sync-latest-release.ps1`）。
- 新增 Inno Setup 安装脚本并内置简体中文语言文件（dd08926、5c3be5f）。
- 补齐仓库此前缺失的构建资产：`tools/7z.exe`、`VERSION`、`requirements-build.txt`、`modules/PW.txt` 占位符等。

## v1.3.9 / v1.3.8（同一源码快照 b307541）

⚠️ 已知历史脏数据：这两个轻量 tag 指向**同一个 commit**，其树中没有 VERSION/installer/scripts/CI；v1.3.8 的 Release 下挂着 `.1`/`.2` 共三套手工上传的增量产物（如 v1.3.8.2），v1.3.9 的 Release 里甚至混有一个名为 `..._v1.3.8_portable.zip` 的资产。**不要尝试对它们做任何重发布或 retag**——外部链接与已分发安装包的身份依赖现状。

## 更早版本

见 GitHub Releases 页面。v1.3.1 及以前的功能说明在 README「更新」一节。
