# 更新日志

版本号遵循 `x.y.z` 三段式（以 VERSION 文件为准）。历史 tag 一律不可移动、不可重打。

## v1.3.11（2026-09-20）

> ⚠️ **请勿使用 v1.3.10。** 该版本是从旧的自解压（WinRAR SFX）分发方式转向官方安装包/自动构建流水线过程中的**转型中间产物**，未经过完整验证即发布，存在以下重大问题：
>
> 1. **右键菜单在所有安装路径下都无法注册。** 注册表写入经过 PowerShell 命令行传参，参数中的引号与空格被破坏，`reg.exe` 收到的是残缺命令行。路径不含空格时错误是静默的——它会写进一个被截断、指向不存在路径的值，用户看到的是"装了但右键没反应"；路径含空格时直接报 `ERROR: Invalid syntax.`。
> 2. **CLI 在输入路径以目录分隔符结尾时会写出自包含压缩包并卡死。** 对 `steg .\folder\` 这类调用，临时 zip 被放在输入目录内部，随后被当作普通文件重新读入并写进自己，体积以约 60 MB/s 膨胀（实测 0.7 秒从 1 MB 涨到 42 MB，首次触发时曾涨到 7.25 GB）。
> 3. **安装界面未沿用 v1.3.9 的既定观感与设置**：没有向导背景图与右上角徽标、没有 EULA 与安装前/后说明页，程序组名退回英文 `SteganographierGUI`（v1.3.9 为「隐写者」）。
>
> 若你已安装 v1.3.10：直接运行 v1.3.11 安装包覆盖安装即可，`modules\PW.txt`、`config.json`、`logs\` 不会被覆盖。装完后请重新执行一次右键菜单安装（开始菜单或安装目录下的 `01-*.cmd`）。

本版本是对上述问题的修复，并把分发形态收拢回 v1.3.9 的既定行为。

### 缺陷修复
- **CLI 临时压缩包自包含**：临时 zip 的落点不再可能落在被压缩目录内部，且压缩包被排除在自身的成员列表之外；收尾删除失败不再掩盖真正的错误（93a76f0、7150cbc）。
- **右键菜单注册表写入**：改为构造完整命令行后交给 `Process.Start` 直接创建进程，不再经过 PowerShell 的参数封送，也不再经过 `cmd /c`（后者会破坏 `&`、`^`、`|`）。已在 9 个含空格、中文、`&`、`!`、`^` 等的恶意路径上验证（2fb69cc，`scripts/test-context-menu-registry-write.ps1`）。
- 修复安装路径含 `!` 时右键菜单路径丢失（延续 v1.3.10 的 PR #30）。

### 回归到 v1.3.9 的既定行为
- 右键菜单的措辞、图标与 PATH 广播方式与 v1.3.9 对齐（0dcd876）。
- 安装向导恢复 v1.3.9 的观感：欢迎页、背景大图与右上角小徽标取自作者原始素材，浅色优先，EULA 与安装前/后说明以 v1.3.9 的 SFX 文本为准（348b0b7、5dc6ccb）。
- 恢复 v1.3.9 的打包选择：`InstallElevated.cmd` 提权助手、程序组名「隐写者」、DownKyi 的取舍、安装后动作；并把 v1.3.9「先清后装」的顺序（先卸旧菜单再装新菜单）在 `[Code]` 中还原（90c1a43）。
- 发行目录布局改用 `_internal/` 承载运行库，与 v1.3.9 一致；右键菜单的实现文件收进 `context-menu/` 子目录，发行根目录由 10 个目录 / 73 个文件收敛为 6 个目录 / 8 个文件（a2830dc、01c26ef）。

### 安装器
- 同时提供**简体中文**与 **English** 两种界面，按系统语言自动选择；窗口标题随语言变化（b8da084）。
- 升级/重装**不再覆盖用户数据**：`modules\PW.txt`、`config.json`、`logs\*` 一律保留；静默（`/SILENT`、`/VERYSILENT`）模式下不弹出任何窗口（365e456）。
- 第三方工具获取脚本固定到作者自己的 DownKyi 构建（`v1.6.1`）并逐文件校验 `MANIFEST.csv`（6c4f412、90c1a43）。

### 工程
- 新增编码守卫 `scripts/test-script-encoding.ps1`：`.ps1` 含非 ASCII 时必须有 UTF-8 BOM，`.cmd`/`.bat` 必须纯 ASCII + CRLF，安装器文本页必须有 BOM + CRLF。
- 打包改用 `pyinstaller==6.11.1`（原 5.13.2 的 `COLLECT` 不支持 `contents_directory`）。

## v1.3.10（2026-08-18，tag: v1.3.10 → 5c3be5f）

> ⚠️ **此版本存在重大问题，不建议使用**，详见上方 v1.3.11 的说明。保留本节仅为记录历史。

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
