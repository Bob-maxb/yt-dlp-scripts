# yt-dlp 下载项目完整指南

> 版本：Complete v2（基于当前 `download-movie.ps1` / `query-JSON-v4.ps1` / `config_movie`）  
> 更新日期：2026-10

---

## 0. 项目概述

本项目用于自动化下载 YouTube 视频，核心能力包括：

- yt-dlp 下载（单视频 / Playlist / **频道 Videos 页**）
- JSON 分析与 Opus 音频智能选择
- PowerShell 自动化流程
- ffmpeg 封装为 MKV
- 多音轨 / 多字幕管理
- Movie / Phonics 两套格式选择规则
- 已完成视频跳过、Playlist 成功/失败统计

**优选组合：**

```text
视频: AV1 > VP9 > AVC1
音频: Opus（多音轨，排除 DUBBED-AUTO）
容器: MKV
字幕: VTT → 嵌入 MKV
```

---

## 1. 目录结构（推荐）

```text
D:\yt-dlp
├── yt-dlp.exe
├── ffmpeg.exe
├── ffprobe.exe
├── cookies.txt
├── config_movie
├── download-movie.ps1
├── query-JSON-v4.ps1
├── Docs
│   └── yt-dlp_Guide_Complete.md
└── Logs
```

**媒体保存位置：**

| Mode    | 根目录                            |
|---------|-----------------------------------|
| Movie   | `D:\03 Media\Movies & TV\`        |
| Phonics | `D:\10 Learning\English\Phonics\` |

**目录规则：**

| 类型 | 路径 |
|------|------|
| 单视频 | `{BaseDir}\Single Files\{视频标题}\` |
| Movie Playlist | `{BaseDir}\Playlist\{Playlist名称}\` |
| Phonics Playlist | `{BaseDir}\{Playlist名称}\` |

每个下载目录下有 `json\` 子目录，存放 `*.info.json` 与 `*.audio-selection.txt`。

---

## 2. 快速开始

### 2.1 单视频（Movie 默认）

```powershell
cd D:\yt-dlp
.\download-movie.ps1 "https://www.youtube.com/watch?v=XXXX"
```

运行时会询问最高分辨率与编码偏好（可直接回车用默认：1080p + AV1）。

### 2.2 单视频 Phonics

```powershell
.\download-movie.ps1 "https://www.youtube.com/watch?v=XXXX" -Mode Phonics
```

### 2.3 Playlist

```powershell
.\download-movie.ps1 "https://www.youtube.com/playlist?list=XXXX"
.\download-movie.ps1 "https://www.youtube.com/playlist?list=XXXX" -Mode Phonics
```

### 2.4 频道 Videos 页（当作 Playlist）

支持类似：

```powershell
.\download-movie.ps1 "https://www.youtube.com/@MissWhitmore"
.\download-movie.ps1 "https://www.youtube.com/@MissWhitmore/videos" -Mode Phonics
```

脚本将频道 `/videos` 列表按 Playlist 方式逐个下载。

### 2.5 只下载指定序号

```powershell
.\download-movie.ps1 "https://www.youtube.com/playlist?list=XXXX" -PlaylistIndexRange "3,5-8,12"
```

支持：`8-11` / `8,10` / `8-11,15,20-22`

### 2.6 指定分辨率与编码（跳过交互询问）

```powershell
.\download-movie.ps1 "VIDEO_URL" -MaxHeight 2160 -PreferCodec av01
.\download-movie.ps1 "PLAYLIST_URL" -MaxHeight 1080 -PreferCodec vp9
```

| 参数 | 可选值 | 默认 |
|------|--------|------|
| `-MaxHeight` | 2160 / 1440 / 1080 / 720 | 1080 |
| `-PreferCodec` | av01 / vp9 / avc1 | av01 |

### 2.7 从剪贴板取链接

```powershell
$url = Get-Clipboard
.\download-movie.ps1 $url -Mode Phonics
```

---

## 3. 整体工作流程

```text
用户运行 download-movie.ps1
        │
        ├─ URL 是 playlist 或 @频道/videos
        │     → 读取列表
        │     → Movie 时只询问一次分辨率/编码
        │     → 按 index 循环调用自身（单个视频）
        │     → 输出成功/失败统计
        │
        └─ 单个视频
              │
              ▼
        STEP 1  query-JSON-v4.ps1
              │  在线查询、定目录、选 Opus 音频
              │  写出 info.json + audio-selection.txt
              │  打印 VIDEO / SUBTITLE / AUDIO 摘要
              │
              ▼
        STEP 2  Format Selection
              │  Phonics：固定规则
              │  Movie：按 MaxHeight / PreferCodec 生成选择器
              │
              ▼
        检查是否已有完整 MKV
              │  Playlist：按 "003 - *.mkv" 前缀匹配
              │  单视频：目录内有 mkv 即跳过
              │  → 跳过则 exit 0
              │
              ▼
        STEP 3  yt-dlp 下载（config_movie）
              │
              ▼
        STEP 4  找最新 MKV
              │
              ▼
        STEP 5  嵌入 English auto-generated 字幕
              │
              ▼
        STEP 6  给字幕轨写 title
              │
              ▼
        CLEANUP  删除临时 .vtt / 封面等
              │
              ▼
        FINAL SUMMARY
```

---

## 4. 格式选择逻辑

### 4.1 Movie 模式

交互或参数决定 `MaxHeight` 与 `PreferCodec` 后：

```text
对每种优先编码：
  独立流  高档 (MinHeight ≤ height ≤ MaxHeight, fps≤60)
  独立流  低档 (height ≤ MinHeight, height≥480, fps≤60)
对每种优先编码：
  已合并  高档
  已合并  低档
最终兜底：b + 选定音频
```

| MaxHeight | MinHeight（高档下限） |
|-----------|------------------------|
| 2160      | 1440                   |
| 1440      | 1080                   |
| 1080      | 720                    |
| 720       | 480                    |

| PreferCodec | 编码顺序          |
|-------------|-------------------|
| av01（默认）| av01 → vp9        |
| vp9         | vp9 → av01        |
| avc1        | avc1 → av01 → vp9 |

### 4.2 Phonics 模式

固定规则（排除 HDR）：

```text
AV1  独立 720p (481–720, ≤30fps, 非 HDR)
 ↓
VP9  独立 720p
 ↓
AV1  独立 480/360p (360–480, ≤30fps, 非 HDR)
 ↓
VP9  独立 480/360p
 ↓
AV1  已合并 720p
 ↓
VP9  已合并 720p
 ↓
AV1  已合并 480/360p
 ↓
VP9  已合并 480/360p
 ↓
AVC1 独立 480/360p
 ↓
AVC1 已合并 480/360p
 ↓
b[height<=720] + 选定音频
```

对应过滤器示例：

```powershell
bv*[vcodec^=av01][height<=720][height>480][fps<=30][dynamic_range!*=HDR]
bv*[vcodec^=av01][height<=480][height>=360][fps<=30][dynamic_range!*=HDR]
```

**设计要点：**

- 用 `height>480` / `height>=360` 区分 720 档与 480 档，避免 480p AV1 抢走 720p VP9
- Phonics 明确排除 HDR
- 独立流优先于已合并流

---

## 5. 音频选择逻辑（query-JSON-v4.ps1）

### 5.1 核心字段

| 字段        | 含义         | 重要性 |
|-------------|--------------|--------|
| format_id   | 音频格式 ID  | ⭐⭐⭐⭐⭐ |
| language    | 语言代码     | ⭐⭐⭐⭐⭐ |
| acodec      | 编码器       | ⭐⭐⭐⭐⭐ |
| abr         | 码率         | ⭐⭐⭐⭐⭐ |
| asr         | 采样率       | ⭐⭐⭐⭐ |
| format_note | 含 DRC 等    | ⭐⭐⭐⭐⭐ |

### 5.2 规则

1. 只选 `acodec` 为 Opus 且 `vcodec=none` 的纯音频
2. 用 URL 中 `xtags` 判断来源：ORIGINAL / DUBBED / DUBBED-AUTO / UNKNOWN
3. **排除 DUBBED-AUTO**
4. 按 Source + Language 分组，每组选最优（优先无 DRC → abr → asr）
5. 写入 `audio-selection.txt`：`SOURCE|lang|format_id`
6. 无 Opus 时回退 `ba*`

`config_movie` 中 `--audio-multistreams` 支持多音轨同时嵌入。

---

## 6. 字幕逻辑

### 6.1 配置（config_movie）

```text
--write-subs
--sub-langs "all"
--sub-format "vtt/best"
--embed-subs
--sleep-subtitles 2
```

### 6.2 脚本后处理

| 步骤 | 作用 |
|------|------|
| STEP 5 | 下载并嵌入 `en-orig`（English auto-generated） |
| STEP 6 | 按 info.json 的 name 写字幕轨 title |
| CLEANUP | 删除外部 .vtt / 封面等 |

### 6.3 注意

- 临时 `.vtt` 文件名可能出现 `en-US.nl-NL` 等（yt-dlp MoveFiles），**不影响** MKV 内轨道元数据
- 播放器显示的是 `language` + `title`，不是临时文件名
- STEP 5 重复运行可能叠加英文字幕 → 依赖「已完成跳过」

---

## 7. 已完成视频跳过

在 STEP 2 与 STEP 3 之间：

| 场景 | 判断方式 |
|------|----------|
| Playlist（PlaylistIndex > 0） | 只认 `003 - *.mkv` 这类带当前序号前缀的文件 |
| 单视频 | 该视频目录内存在任意 `.mkv` 即跳过 |

- 跳过 → `exit 0`（Playlist 计为成功）
- 不完整残留 → 依赖 yt-dlp `--continue` 续传

STEP 1 / STEP 2 仍会执行（查询较快）。

---

## 8. Playlist 最终统计

```text
PLAYLIST COMPLETE
Playlist      : xxx
Total items   : 12
Succeeded     : 10
Failed        : 2

=== DETAILED RESULTS ===
INDEX  STATUS  ID           TITLE
1      OK      abc123       Video A
2      FAILED  def456       Video B
```

被 `-PlaylistIndexRange` 跳过的条目不进入统计。

---

## 9. 脚本参数一览

| 参数 | 说明 | 默认 |
|------|------|------|
| `Url` | 视频 / Playlist / 频道 URL（必填） | — |
| `PlaylistTitle` | 内部递归传入，用户一般不填 | `""` |
| `Mode` | `Movie` / `Phonics` | `Movie` |
| `PlaylistIndex` | 内部递归传入的序号 | `0` |
| `PlaylistIndexRange` | 只下载指定序号 | `""` |
| `MaxHeight` | Movie 最高分辨率 | `0`（触发询问） |
| `PreferCodec` | Movie 编码偏好 | `""`（触发询问） |

---

## 10. 配置文件要点（config_movie）

```text
--remote-components ejs:github
--extractor-args "youtube:player_client=default,web_embedded;skip=translated_subs"
--audio-multistreams
--merge-output-format mkv
--write-subs
--sub-langs "all"
--sub-format "vtt/best"
--embed-subs
--write-thumbnail
--embed-thumbnail
--embed-chapters
--embed-metadata
--continue
--ignore-errors
--sleep-interval 5
--max-sleep-interval 10
```

---

## 11. VIDEO FORMAT SUMMARY 显示字段

查询时打印（仅展示，不参与选择）：

| 列 | 含义 |
|----|------|
| ID | format_id |
| CODEC | vcodec |
| RESOLUTION | 宽x高 |
| FPS | 帧率 |
| VBR | 视频码率（无则用 tbr 近似） |
| SIZE | filesize / filesize_approx |
| HDR | dynamic_range 或推断 SDR/HDR |
| TYPE | video-only / video+audio |

---

## 12. 常用手动命令

### 查看在线格式

```powershell
.\yt-dlp.exe -F --cookies cookies.txt --remote-components ejs:github --extractor-args "youtube:player_client=default,web_embedded" "VIDEO_URL"
```

### 查看字幕

```powershell
.\yt-dlp.exe --list-subs --sub-langs "en.*,zh.*" --cookies cookies.txt --remote-components ejs:github --extractor-args "youtube:player_client=default,web_embedded" "VIDEO_URL"
```

### 仅查询 JSON

```powershell
.\query-JSON-v4.ps1 "VIDEO_URL" -Mode Phonics
```

### 检查本地 MKV 字幕轨道

```powershell
.\ffprobe -v error -select_streams s -show_entries stream_tags=language,title -of csv=p=0 "完整路径\文件.mkv"
```

### 检查脚本语法

```powershell
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile(
  "D:\yt-dlp\download-movie.ps1", [ref]$tokens, [ref]$errors
) | Out-Null
$errors | ForEach-Object {
  "Line $($_.Extent.StartLineNumber), Col $($_.Extent.StartColumnNumber): $($_.Message)"
}
```

无输出即语法通过。

---

## 13. --download-archive（可选）

```text
--download-archive "D:\yt-dlp\download-archive.txt"
```

- 成功下载后写入视频 ID
- 下次同一 ID 直接跳过
- 建议绝对路径；可与「已有 MKV 跳过」双保险

当前脚本默认未启用。

---

## 14. 故障排查

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| 480p AV1 抢在 720p VP9 前 | 旧版 `height<=720` 过宽 | 使用 `height>480` / `height>=360` |
| Playlist 有一个 mkv 就全跳过 | 跳过逻辑未按序号前缀 | 使用 `003 - *.mkv` 匹配 |
| 重复英文字幕 | 对已完成文件再跑 STEP 5 | 依赖已完成跳过 |
| 选到 format 18 等低画质 | 高档过滤过严，全部不匹配后落到 `b+` | 放宽 height/fps 或检查实际可用格式 |
| 下载失败 / JS challenge | cookies 过期 | 更新 cookies.txt |
| ffprobe Permission denied | 路径是文件夹不是文件 | 使用完整 `.mkv` 路径 |
| Playlist 每个视频都问分辨率 | 未把 MaxHeight 传给子进程 | 确认递归调用带 `-MaxHeight` `-PreferCodec` |

---

## 15. 设计原则

1. **容器固定 MKV** — 多音轨、多字幕、章节支持最好  
2. **音频固定 Opus** — 效率高；排除自动配音轨  
3. **字幕 VTT 并嵌入** — 质量与兼容平衡  
4. **Phonics ≤30fps、偏 720/480、排除 HDR** — 学习向体积控制  
5. **Movie 可交互选分辨率/编码** — Playlist 只问一次  
6. **已完成可安全重跑** — 按文件/序号跳过，避免重复封装  

---

## 16. 补充备忘

**编码优先级：** AV1 > VP9 > AVC1（H.264）  
**音频优先级：** Opus > AAC  

**体积粗算（码率 kbps、时长秒）：**

```text
文件大小 (MiB) ≈ 总码率(kbps) × 时长(秒) / 8388.608
总码率 ≈ 视频码率 + 音频码率
```

**容器/字幕测试结论：**

- 优选：`视频 + Opus + MKV + VTT 嵌入`
- iPhone 对 AV1 支持有限；MKV+Opus 在桌面播放器表现最佳

**自动关机（可选）：**

```powershell
if ($LASTEXITCODE -eq 0) { shutdown /s /t 60 }
# 取消：shutdown /a
```

---

## 17. 脚本职责

| 文件 | 职责 |
|------|------|
| `download-movie.ps1` | 主流程、Playlist/频道循环、格式选择、下载、后处理、统计、跳过 |
| `query-JSON-v4.ps1` | 在线查询、目录计算、音频选择、格式/字幕摘要展示 |
| `config_movie` | yt-dlp 全局下载与封装参数 |

---

*文档结束。脚本有新增参数或规则变更时，请同步修订本节。*

## 16. Appendy
AV1优于VP9优于AVC1(H.264)
OPUS优于AAC

当码率单位为 kbps、时长单位为秒时：

文件大小（MiB）≈8388.608总码率（kbps）×时长（秒）​/8388.608

总码率通常可以估算为：

总码率=视频码率+音频码率

如果还包含字幕、封面、元数据等，实际文件会略大一些。

测试
summary sv1+opus+mkv+sub ✔  iPhone 原生无法播放视频部分；sv1+opus+webm+sub只能加载webmtt字幕 ❌ ；sv1+opus+mp4+sub只支持mov_text和tx3g字幕 ❌；sv1+aac+mkv+sub ✔文件增大iPhone依然无法播放且aac效率低于opus  ；v1+aac+mp4+sub只支持mov_text和tx3g字幕 ❌  ;v1+aac+webm+sub webm不支持这样的容器组合 ❌
✔所有优选选择sv1+opus+mkv+sub 组合
字幕选择VTT最优

封装字幕
.\ffmpeg -i "How to describe different sizes in English.mp4" -i "How to describe different sizes in English [QpEGDf3WAn8].es-US.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].en-orig.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].pt-BR.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].ja.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].it.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].id.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].hi.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].de-DE.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].fr-FR.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].en.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].zh-Hans.srt" -map 0 -map 1 -map 2 -map 3 -map 4 -map 5 -map 6 -map 7 -map 8 -map 9 -map 10 -map 11 -c copy -metadata:s:s:0 language=es-US -metadata:s:s:1 language=en-orig -metadata:s:s:2 language=pt-BR -metadata:s:s:3 language=ja -metadata:s:s:4 language=it -metadata:s:s:5 language=id -metadata:s:s:6 language=hi -metadata:s:s:7 language=de-DE -metadata:s:s:8 language=fr-FR -metadata:s:s:9 language=en -metadata:s:s:10 language=zh-Hans "How to describe different sizes in English sub.mp4"


yt-dlp原生命令
下载命令
下载普通 YouTube 视频：
.\yt-dlp.exe --config-location "D:\yt-dlp\config_phonics Minimum AVC1 480P" "https://www.youtube.com/watch?v=XlxEE41JHK4"

.\yt-dlp.exe --config-location "D:\yt-dlp\config_phonics Minimum AVC1 480P" "https://www.youtube.com/watch?v=aftne3KaXEM"

如果是 Playlist：
.\yt-dlp.exe --config-location "D:\yt-dlp\config_phonics Minimum AVC1 480P" "https://www.youtube.com/playlist?list=XXXXXXXXXXX"


如果需要 cookies
.\yt-dlp.exe --cookies cookies.txt --config-location "D:\yt-dlp\config_phonics AVC1 + Opus" "https://www.youtube.com/watch?v=QpEGDf3WAn8"



如果是 Playlist：
.\yt-dlp.exe --cookies cookies.txt --config-location "D:\yt-dlp\config_phonics" "https://www.youtube.com/playlist?list=PLToJJ2R3kEHqDaSE5GxLX2JgkXo0EzO3E&index=1"





查询在线视频编码coding
.\yt-dlp.exe -F --cookies cookies.txt --remote-components ejs:github --extractor-args "youtube:player_client=default,web_embedded" "https://www.youtube.com/watch?v=SkorusaTwbw"; .\yt-dlp.exe --list-subs --sub-langs "en.*,zh.*" --cookies cookies.txt --remote-components ejs:github --extractor-args "youtube:player_client=default,web_embedded" "https://www.youtube.com/watch?v=SkorusaTwbw"


检查脚本语法的命令
$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("D:\yt-dlp\query-JSON-v4.ps1",[ref]$tokens,[ref]$errors) | Out-Null; $errors | ForEach-Object { "Line $($_.Extent.StartLineNumber), Col $($_.Extent.StartColumnNumber): $($_.Message)" }
没有任何输出：语法检查通过。