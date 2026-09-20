# 第三方伴随工具：B站视频下载工具 DownKyi

README §5.2 将 [DownKyi](https://github.com/leiurayer/downkyi)（MIT，C#/.NET WPF）列为推荐的"隐写外壳下载工具"。包内附带一份 `B站视频下载工具-DownKyi-1.6.1/`（含 `aria2_COPYING.txt`、`FFmpeg_LICENSE.txt` 等许可证文件）。

## 现状与规则

- DownKyi **不是 git 跟踪的构建输入**，但**是正式构建输入**：由 `scripts/fetch-thirdparty.ps1` 按固定 URL + SHA256 拉取到 `.thirdparty-cache/`（已 gitignore），再由 `scripts/build-release.ps1` 拷入 stage。因此**便携包与安装器都会包含它**。
- 唯一允许的引入方式是上述脚本；**禁止再把本地目录手工塞进 stage**——那正是自 v1.3.10 起它从发布包中消失的原因（CI 全自动产物不会带上手工塞的东西）。
- `scripts/smoke-test.ps1` 会断言 stage 里存在该目录及两份上游许可证文件，避免"静默丢失"。

## 固定版本与校验

| 项 | 值 |
|---|---|
| 上游 | `leiurayer/downkyi` |
| 版本 | `v1.6.1` |
| 资产 | `DownKyi-1.6.1.zip` |
| 大小 | 32,204,639 字节 |
| SHA256 | `d809c230c9dd9ab18a7cbafc413db2d93eca25e45c4df5fa6aaad3f253015986` |
| 包内目录名 | `B站视频下载工具-DownKyi-1.6.1`（沿用旧版命名，便于老用户识别） |

校验是 fail-closed 的：**每次构建**都重新核对大小与 SHA256（缓存文件也核），不一致即中止，绝不打包未经校验的压缩包。升级版本时同步修改这三个字段。

### 一处已知差异

上游 `v1.6.1` 资产解出的 36 个文件中，**35 个与历史 v1.3.9 包内副本逐字节相同**；唯一不同的是 `DownKyi.Core.dll`：

| 来源 | 大小 |
|---|---|
| 上游 `v1.6.1` 官方资产 | 542,720 字节 |
| 历史 v1.3.9 包内副本 | 597,504 字节 |

采用**上游官方版本**：它可哈希校验且来源明确；v1.3.9 包内那份 597,504 字节的 DLL 无法追溯来源（GitHub release asset 的 `created_at`/`updated_at` 仅相差 2 分钟，说明资产未被事后替换过）。若需要可单独调查该差异，但不应继续分发来源不明的二进制。

## 解压必须用 7z，不能用 Expand-Archive

上游 zip **没有设置 UTF-8 文件名标志**，`Expand-Archive` 会把 `打不开DownKyi请点我.txt` 解成乱码（已实测）。`scripts/fetch-thirdparty.ps1` 因此调用仓库自带的 `tools\7z.exe` 解压。

## 本机使用约定

DownKyi 也可作为独立便携工具维护（如 `<tools-root>\downkyi-1.6.1\`），需要时把下载的外壳视频放入安装目录的 `cover_video\`。程序运行不依赖 DownKyi 存在于任何位置。
