# 第三方伴随工具：B站视频下载工具 DownKyi

README §5.2 将 [DownKyi](https://github.com/leiurayer/downkyi)（MIT，C#/.NET WPF）列为推荐的"隐写外壳下载工具"。包内附带 `B站视频下载工具-DownKyi-1.6.1/`（含 `aria2_COPYING.txt`、`FFmpeg_LICENSE.txt` 等许可证文件）。

## 权威件是**作者自己调整过的 1.3.9 版本**，不是上游发行版

包内这一份是**作者单独调整过的构建**，因此：

- **以 v1.3.9 安装包内那一份为唯一权威**，不以 GitHub 上游 `v1.6.1` 发行版为准。
- 该份与上游 `v1.6.1` 逐文件比对的结果：**36 个文件中 35 个逐字节相同**，唯一差异是 `DownKyi.Core.dll`
  （上游 542,720 字节 / 作者版 **597,504 字节**，sha256 `3681e5fe31c97491b117954003bdf36871d527742fe7638d9b0c45eaabf12f91`）。
- 该差异是**作者的改动，不是来源不明的二进制**。此前一版文档把它当作可疑项并建议改用上游文件，**该建议是错的，已撤销**。

## 落地方式（为什么只把 1 个文件放进 git）

| 部分 | 存放方式 | 理由 |
|---|---|---|
| 作者的 `DownKyi.Core.dll` | **git 跟踪**：`vendor/downkyi-1.6.1/overrides/DownKyi.Core.dll`（583 KB） | 它**无法从任何公开来源复现**，只有 git 能作为单一事实来源长期保存 |
| 其余 35 个文件（含 `ffmpeg.exe` 61 MB、`aria2c.exe`、许可证） | 构建时从**固定 URL + SHA256** 的上游归档取用 | 与上游逐字节相同，公开可复现；避免把 75 MB 压进 git 历史（历史膨胀不可逆） |
| 期望终态 | **git 跟踪**：`vendor/downkyi-1.6.1/MANIFEST.csv`（36 行，UTF-8 BOM + CRLF） | 验收依据 |

`scripts/fetch-thirdparty.ps1` 的流程：下载→校验归档大小/SHA256→7z 解压→**覆盖应用 tracked overrides**→拷入 stage→**对全部 36 个文件逐个核对 MANIFEST 的大小与 SHA256，并拒绝清单外的多余文件**。

因此验收声明不是"我们下载对了压缩包"，而是**"stage 出来的目录与作者认可的构建逐字节一致"**。实测：stage 结果与 v1.3.9 载荷**36/36 全部相同**。

## 版本与校验

| 项 | 值 |
|---|---|
| 上游 | `leiurayer/downkyi` `v1.6.1` |
| 归档 | `DownKyi-1.6.1.zip`，32,204,639 字节 |
| 归档 SHA256 | `d809c230c9dd9ab18a7cbafc413db2d93eca25e45c4df5fa6aaad3f253015986` |
| 包内目录名 | `B站视频下载工具-DownKyi-1.6.1`（沿用旧版命名） |

归档大小与 SHA256 **每次构建都重新核对**（缓存文件也核），不一致即中止。升级上游时同步修改脚本中的三个字段；若新版上游不再能复现认可构建，MANIFEST 会使其**失败而不是静默出厂**。

## 解压必须用 7z，不能用 Expand-Archive

上游 zip **没有设置 UTF-8 文件名标志**，`Expand-Archive` 会把 `打不开DownKyi请点我.txt` 解成乱码（已实测）。脚本因此调用仓库自带的 `tools\7z.exe`。

## 变更记录的可靠性

MANIFEST 与 overrides 是**可核对**的：任何一处不一致（少一个文件、大小不符、SHA256 不符、多出文件）都会让构建失败。已用变异测试验证过两条关键路径：移除 overrides → 报 `size: DownKyi.Core.dll (staged 542720, approved 597504)`；篡改 MANIFEST → 报 `sha256: DownKyi.Core.dll`。

## 缓存

载荷（归档 + 解压树，约 106 MB）放在 `.thirdparty-cache/`（已 gitignore），仅作构建缓存；删除后下次构建会重新下载。**它不是构建输入**，构建输入是 git 里的 MANIFEST 与 overrides。

## 本机使用约定

DownKyi 也可作为独立便携工具维护（如 `<tools-root>\downkyi-1.6.1\`），需要时把下载的外壳视频放入安装目录的 `cover_video\`。程序运行不依赖 DownKyi 存在于任何位置。
