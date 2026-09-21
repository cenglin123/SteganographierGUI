# 第三方伴随工具：B站视频下载工具 DownKyi

README §5.2 将 [DownKyi](https://github.com/leiurayer/downkyi)（MIT，C#/.NET WPF）列为推荐的"隐写外壳下载工具"。包内附带 `B站视频下载工具-DownKyi-1.6.1/`（含 `aria2_COPYING.txt`、`FFmpeg_LICENSE.txt` 等许可证文件）。

## 权威件是**作者自己调整过的 1.3.9 版本**，不是上游发行版

包内这一份是**作者单独调整过的构建**，因此：

- **以 v1.3.9 安装包内那一份为唯一权威**，不以 GitHub 上游 `v1.6.1` 发行版为准。
- 该份与上游 `v1.6.1` 逐文件比对的结果：**36 个文件中 35 个逐字节相同**，唯一差异是 `DownKyi.Core.dll`
  （上游 542,720 字节 / 作者版 **597,504 字节**，sha256 `3681e5fe31c97491b117954003bdf36871d527742fe7638d9b0c45eaabf12f91`）。
- 该差异是**作者的改动，不是来源不明的二进制**。此前一版文档把它当作可疑项并建议改用上游文件，**该建议是错的，已撤销**。

## 这份 `DownKyi.Core.dll` 的来源：上游 issue #1171

**已定位到确切来源，并逐字节确认。** 它来自 [leiurayer/downkyi#1171](https://github.com/leiurayer/downkyi/issues/1171)
（"登录二维码显示不了的原因和解决代码"）回复里的附件：

| 项 | 值 |
|---|---|
| 附件 | `DownKyi.Core.dll.zip`，211,360 字节，sha256 `f07dfceb7287c91b3c93943852d54d981f2d522b6dee1d01a70b6b3bf48cf146` |
| 下载地址 | `https://github.com/user-attachments/files/17556618/DownKyi.Core.dll.zip` |
| 解出的 `DownKyi.Core.dll` | 597,504 字节，sha256 `3681e5fe31c97491b117954003bdf36871d527742fe7638d9b0c45eaabf12f91` |
| 与包内 overrides 比对 | **逐字节相同** |

所以包内这份不是来源不明的二进制，也**不是**"无法从任何公开来源复现"——把上面那个附件下载下来比对哈希即可复现。
（本文档上一版写过"无法从任何公开来源复现"，那是在只核对过上游归档与 #1874 附件之后下的结论，**已作废**。）

### 它修的是什么

上游 1.6.x 的**登录二维码显示不出来**：B站返回的二维码 URL 太长，`DownKyi.Core.Utils.QRCode.createQrCode`
里设置的纠错级别（`QRCoder.QRCodeGenerator.ECCLevel.H`）生成不了这么长的 URL，于是抛异常。#1171 给出的
解决办法是把纠错级别降到 `L`；该附件就是照这个思路重新编译出来的 `DownKyi.Core.dll`。

### 别和 #1874 混淆

同一个"登录"话题下还有 [leiurayer/downkyi#1874](https://github.com/leiurayer/downkyi/issues/1874)，那是**另一个**
问题（扫码后**登录信息未保存**，手机上确认了登录仍回登录页），附件是另一份文件。三份文件实测互不相同：

| 来源 | 大小 | SHA256 |
|---|---|---|
| 上游 `v1.6.1` 归档内的原件 | 542,720 | `6fe0e72c6c664ad8a5c6cd03f4e6a0fa4abf1577559cd4dc0d82524dfb503180` |
| **包内这份（= #1171 附件）** | 597,504 | `3681e5fe31c97491b117954003bdf36871d527742fe7638d9b0c45eaabf12f91` |
| #1874 附件 `fix.zip` 内 | 592,384 | `400ac85638f77a0e6d921ee02aff6644b48958490c54c4b8c6d1e345ed4602a1` |

三者的 `FileVersion` 都是 `2.2.1.0`，**版本号区分不出来，只能比字节**。#1874 的附件另附一个
`DownKyi.LoginFix.dll`（7,168 字节），包内没有该文件。**不要把 #1874 的附件当作我们这份的来源或替代品**；
反过来，包内这份修的也不是 #1874 的登录保存问题。

关于 #1874 那份社区补丁另有一点值得记：它的作者自述**取消了登录文件的硬件绑定**，并提醒不要外传生成的
`Config/Login`。包内这份是否做了同样的事，本文档不作断言——无法从二进制断定。

### 能核到什么程度

- **能**：来源锚定到具体 issue 的具体附件，且逐字节一致，因此它不是无人认领的二进制，任何人可自行复现比对。
- **不能**：无法用字节比对确认"改动仅限于那一个纠错级别常量"。实测它相对上游有 **93.3% 的字节不同、
  约 3 万个不连续差异段**，说明这是**用不同编译设置整体重新编译过的程序集**，不是改几个字节。
  也就是说，这份二进制的可信度建立在"来源可核 + 用途单一"之上，而不是建立在二进制审计之上。
- 要彻底去掉这一层，唯一的办法是由本项目用上游源码自行编译这份修复（改动量是 `QRCode.cs` 里一处枚举值），
  使其成为完全自建、可复现的产物。**这是留给作者的选项，本文档只记录现状。**

## 落地方式（为什么只把 1 个文件放进 git）

| 部分 | 存放方式 | 理由 |
|---|---|---|
| 作者的 `DownKyi.Core.dll` | **git 跟踪**：`vendor/downkyi-1.6.1/overrides/DownKyi.Core.dll`（583 KB） | 来源虽已锚定到 issue #1171 的附件（见上节），但那是**第三方 issue 里的个人附件**，既不是 release asset，也随时可能被删改——构建不应从这种位置取二进制。由 git 作为单一事实来源长期保存 |
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

上游 `v1.6.1` 的 Release **只有 `DownKyi-1.6.1.zip` 一个附件**，与上表一致。（#1874 的讨论里有人报告 1.6.1 出现 `DownKyi.exe` 与 `DownKyi.Core.dll` 版本不匹配并崩溃，那是他自己打了 [#1845](https://github.com/leiurayer/downkyi/issues/1845) 补丁的构建，不是官方 asset。）我们的流水线对 36 个文件逐个核对 MANIFEST，这类不一致只会让构建失败，不会出厂。

## 解压必须用 7z，不能用 Expand-Archive

上游 zip **没有设置 UTF-8 文件名标志**，`Expand-Archive` 会把 `打不开DownKyi请点我.txt` 解成乱码（已实测）。脚本因此调用仓库自带的 `tools\7z.exe`。

## 变更记录的可靠性

MANIFEST 与 overrides 是**可核对**的：任何一处不一致（少一个文件、大小不符、SHA256 不符、多出文件）都会让构建失败。已用变异测试验证过两条关键路径：移除 overrides → 报 `size: DownKyi.Core.dll (staged 542720, approved 597504)`；篡改 MANIFEST → 报 `sha256: DownKyi.Core.dll`。

## 缓存

载荷（归档 + 解压树，约 106 MB）放在 `.thirdparty-cache/`（已 gitignore），仅作构建缓存；删除后下次构建会重新下载。**它不是构建输入**，构建输入是 git 里的 MANIFEST 与 overrides。

## 本机使用约定

DownKyi 也可作为独立便携工具维护（如 `<tools-root>\downkyi-1.6.1\`），需要时把下载的外壳视频放入安装目录的 `cover_video\`。程序运行不依赖 DownKyi 存在于任何位置。
