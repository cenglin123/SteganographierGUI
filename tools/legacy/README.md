# tools/legacy — 已退役运行时脚本存档

本目录保存**不再被当前构建链生成、但旧装机环境的注册表项可能仍在调用**的运行时脚本，仅作抢救性归档（2026-09-12 自本机 v1.3.8.2 安装目录提取；git 全历史此前从未跟踪过它们）。

| 文件 | 旧作用 | 现状 |
|---|---|---|
| `run_hash_modifier.ps1` | 旧版右键"修改文件哈希"的包装器：调 `hash_modifier.exe` + 写日志 + 弹托盘通知。旧 CommandStore 项 `modifyHash` 的 command 值直接指向它。 | 新版 `context-menu/Install-ContextMenu.ps1` 已改为直接调用 `hash_modifier.exe "%1"`，不再需要此包装器。升级时先跑旧版 Uninstall 或重跑 Install 覆盖注册表即可摆脱对它的引用。 |
| `steg.bat` | 旧版 `steg` 命令行入口（硬编码绝对路径），由旧 `01-*.bat` 现场生成并加入 Machine PATH。 | 新版体系改用 `tools\steg.cmd`（由 Install-ContextMenu.ps1 生成，路径随安装位置推导）。 |

**规则**：不要把这些脚本拷回新装机——重装后请运行 `01-安装隐写者到右键菜单.cmd` 重建规范的注册表/PATH 状态。若发现某台机器的注册表仍指向 `tools\run_hash_modifier.ps1`，正确处置是重跑安装脚本，而不是恢复此文件。
