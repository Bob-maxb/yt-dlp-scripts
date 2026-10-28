# yt-dlp 下载项目完整指南

> 版本：Complete v5  
> 适用脚本：  
> - **YouTube：** `download-youtube.ps1` / `query-youtube.ps1` / `config_youtube`  
>   （旧名仍可能使用：`download-movie.ps1` / `query-JSON-v4.ps1` / `config_movie`）  
> - **其它网站：** `download-generic.ps1` / `query-generic.ps1` / `config_generic`  
> 更新日期：2026-10-28

---

## 0. 项目概述

自动化下载 **YouTube** 与 **其它 yt-dlp 支持站点** 的视频，核心能力：

- 单视频 / Playlist / 频道 Videos 页（`@Name` / `@Name/videos`）
- `watch?v=...&list=...` 链接交互选择：只下本集或整表
- JSON 分析与 Opus 多音轨选择（排除 DUBBED-AUTO；无 Opus 时 AAC / `ba*`）
- Movie / Phonics 两套格式规则
- 已完成 MKV 跳过、Playlist 成功/失败统计
- 字幕嵌入、临时文件清理（兼容标题中的 `[]` 等特殊字符）
- **Generic 脚本：** 非 YouTube 站点单视频 / 简易 Playlist（逻辑对齐 YouTube 版）
- **交互 Mode：** 未指定 `-Mode` 时询问 Movie / Phonics（YouTube + Generic）
- **Generic Adult：** 可选保存到 `D:\03 Media\Adult`（默认否）
- **Generic 成品：** 识别 `mkv` / `mp4` / `webm`（跳过与 STEP 4）

**优选组合：**

```text
视频: AV1 > VP9 > AVC1
音频: Opus（多音轨）
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
├── cookies.txt                 # 勿上传 GitHub
├── youtube\                    # YouTube 专用脚本
│   ├── download-youtube.ps1    # 旧名 download-movie.ps1
│   ├── query-youtube.ps1       # 旧名 query-JSON-v4.ps1
│   └── config_youtube          # 旧名 config_movie
├── generic\                    # 其它网站脚本
│   ├── download-generic.ps1
│   ├── query-generic.ps1
│   └── config_generic
├── yt-dlp-git\                 # Git 同步用（可选）
│   └── yt-dlp_Guide_Complete.md
└── ...
```

**路径约定（脚本在子目录时）：**

```powershell
$Root        = "D:\yt-dlp"                              # exe、cookies
$YtDlp       = Join-Path $Root "yt-dlp.exe"
$Config      = Join-Path $PSScriptRoot "config_youtube" # 与 ps1 同目录
$QueryScript = Join-Path $PSScriptRoot "query-youtube.ps1"
$Cookies     = Join-Path $Root "cookies.txt"
```

- `$PSScriptRoot`：PowerShell **自动变量**，= 当前脚本所在目录，**无需自己赋值**。
- 必须用 `.\download-youtube.ps1` 等方式**运行文件**；在控制台粘贴整段代码时 `$PSScriptRoot` 可能为空。

**媒体保存位置：**

| Mode / 选项 | 根目录 |
|-------------|--------|
| Movie（默认） | `D:\03 Media\Movies & TV\` |
| Movie + Adult（仅 generic） | `D:\03 Media\Adult\` |
| Phonics | `D:\10 Learning\English\Phonics\` |

| 类型 | 路径 |
|------|------|
| 单视频 | `{BaseDir}\Single Files\{视频标题}\` |
| Movie Playlist | `{BaseDir}\Playlist\{Playlist名称}\` |
| Phonics Playlist | `{BaseDir}\{Playlist名称}\` |

每集目录下有 `json\`（`*.info.json`、`*.audio-selection.txt`）。

---

## 2. 快速开始

### 2.0 脚本位置与名称对照

| 用途 | 目录 | 脚本 |
|------|------|------|
| YouTube | `D:\yt-dlp\youtube\` | `.\download-youtube.ps1` |
| 其它站 | `D:\yt-dlp\generic\` | `.\download-generic.ps1` |

旧命令若仍指向根目录的 `download-movie.ps1`，请改为上述路径，或继续把脚本放在根目录并用旧文件名。

### 2.1 单视频（Movie 默认）

```powershell
cd D:\yt-dlp\youtube
.\download-youtube.ps1 "https://www.youtube.com/watch?v=XXXX"
```

未加 `-Mode` 时会先问：

```text
Download mode?
  1 = Movie   (default)
  2 = Phonics
```

Movie 时再询问最高分辨率与编码（直接回车 = 1080p + AV1）。

### 2.2 Phonics

```powershell
.\download-youtube.ps1 "https://www.youtube.com/watch?v=XXXX" -Mode Phonics
```

### 2.3 Playlist

```powershell
.\download-youtube.ps1 "https://www.youtube.com/playlist?list=XXXX"
.\download-youtube.ps1 "https://www.youtube.com/playlist?list=XXXX" -Mode Phonics
```

### 2.4 频道 Videos 页

```powershell
.\download-youtube.ps1 "https://www.youtube.com/@MissWhitmore"
.\download-youtube.ps1 "https://www.youtube.com/@MissWhitmore/videos" -Mode Phonics
```

### 2.5 带 list 的 watch 链接（交互）

```text
https://www.youtube.com/watch?v=VIDEO_ID&list=PLAYLIST_ID
```

运行后询问：

```text
1 = 只下当前这一集（默认）
2 = 下载整个 playlist
```

仍可加 `-Mode`、`-MaxHeight` 等：

```powershell
.\download-youtube.ps1 "https://www.youtube.com/watch?v=xxx&list=PLyyy" -Mode Phonics
.\download-youtube.ps1 "https://www.youtube.com/watch?v=xxx&list=PLyyy" -MaxHeight 1080 -PreferCodec av01
```

### 2.6 只下载指定序号

```powershell
.\download-youtube.ps1 "https://www.youtube.com/playlist?list=XXXX" -PlaylistIndexRange "3,5-8,12"
```

格式：`8-11` / `8,10` / `8-11,15,20-22`

### 2.7 指定分辨率与编码（Movie，跳过询问）

```powershell
.\download-youtube.ps1 "URL" -MaxHeight 2160 -PreferCodec av01
```

| 参数 | 可选值 | 默认 |
|------|--------|------|
| `-MaxHeight` | 2160 / 1440 / 1080 / 720 | 1080 |
| `-PreferCodec` | av01 / vp9 / avc1 | av01 |

### 2.8 剪贴板

```powershell
$url = (Get-Clipboard).Trim()
$url
.\download-youtube.ps1 $url -Mode Phonics
```

两行命令一起运行：

```powershell
$url = Get-Clipboard; .\download-youtube.ps1 $url -Mode Phonics
```

### 2.9 其它网站（generic）

```powershell
cd D:\yt-dlp\generic
.\download-generic.ps1 "https://www.bilibili.com/video/BVxxxx"
.\download-generic.ps1 "URL" -Mode Phonics
.\download-generic.ps1 "URL" -MaxHeight 1080
.\download-generic.ps1 "URL" -Adult
```

先确认站点支持：

```powershell
D:\yt-dlp\yt-dlp.exe -F "视频URL"
```

说明：

- 无 `upload_date` 时用当天日期，不中断查询
- 音频：Opus → AAC → 任意纯音轨 → `ba*`
- 非 YouTube 不加 youtube `extractor-args`
- Playlist：若 yt-dlp 能返回 `entries` 则循环；否则按单 URL
- 日常 YouTube 仍建议用 `youtube\` 下脚本
- **Mode 交互：** 未写 `-Mode` 时询问 1=Movie / 2=Phonics（与 YouTube 相同）
- **Adult 交互（仅 Movie）：** 默认 N → `Movies & TV`；Y 或 `-Adult` → `D:\03 Media\Adult`
- **成品扩展名：** 跳过与 STEP 4 识别 `mkv` / `mp4` / `webm`（部分站只有 HLS→mp4）

### 2.10 交互询问汇总（v5）

| 询问 | YouTube | Generic | 何时跳过 |
|------|---------|---------|----------|
| Mode（Movie/Phonics） | 有 | 有 | 已传 `-Mode` |
| Adult（是否成人目录） | 无 | 有（仅 Movie） | 已传 `-Adult`，或 Mode=Phonics |
| 单集/整表（watch+list） | 有 | 无 | 递归子任务已带 PlaylistTitle |
| 分辨率/编码 | Movie 有 | Movie 有 | 已传 `-MaxHeight` / `-PreferCodec` |

---

## 3. 整体工作流程

```text
download-youtube.ps1
    │
    ├─ 未指定 -Mode → 询问 Movie / Phonics（默认 Movie）
    │
    ├─ 若 watch?v= + list= 且非递归子任务
    │     → 询问：单集 / 整表（整表则改写为 playlist URL）
    │
    ├─ URL 为 playlist 或 @频道/videos
    │     → 拉列表
    │     → Movie：分辨率/编码只问一次，传给每个子任务
    │     → 循环调用自身
    │     → 输出成功/失败统计
    │
    └─ 单个视频
          → STEP 1  query-youtube（查询、目录、音频选择）
          → STEP 2  格式选择器（Movie / Phonics）
          → 已有完整 MKV？→ 跳过 exit 0
          → STEP 3  yt-dlp 下载
          → STEP 4  找 MKV
          → STEP 5  English auto 字幕
          → STEP 6  字幕 title
          → CLEANUP 临时文件（LiteralPath，支持 [] 标题）
          → FINAL SUMMARY
```

**generic 流程：** 与上类似；另有 Adult 目录询问；Playlist 为可选启发式；格式链含通用 `height` 兜底；成品认 mkv/mp4/webm；ffmpeg 调用已做 stderr 静默（兼容 Windows PowerShell 5.1）。

---

## 4. 格式选择逻辑

### 4.1 Movie（与 Phonics 同结构，分辨率更高）

由 `MaxHeight` + `PreferCodec` 决定。

**编码优先级：**

| PreferCodec | 主循环顺序 | 之后 |
|-------------|------------|------|
| av01（默认）| av01 → vp9 | 再 AVC1 各档 |
| vp9         | vp9 → av01 | 再 AVC1 各档 |
| avc1        | avc1 → av01 → vp9 | 不再重复挂 AVC1 |

**选择顺序（对齐 Phonics）：**

```text
1. 主编码 独立 最高档
2. 主编码 独立 次高档
3. 主编码 已合并 最高档
4. 主编码 已合并 次高档
5. （若主循环无 avc1）AVC1 独立/已合并 最高与次高
6. b + 选定音频（兜底）
```

| MaxHeight | 最高档 | 次高档约 |
|-----------|--------|----------|
| 2160 | 1440 < h ≤ 2160 | h ≤ 1440 且 h ≥ 480 |
| 1440 | 1080 < h ≤ 1440 | h ≤ 1080 且 h ≥ 480 |
| 1080 | 720 < h ≤ 1080 | h ≤ 720 且 h ≥ 480 |
| 720  | 480 < h ≤ 720  | h ≤ 480 且 h ≥ 480 |

Movie 使用 `fps≤60`。

### 4.2 Phonics

固定、排除 HDR、`fps≤30`：

```text
AV1 独立 720 → VP9 独立 720
 → AV1 独立 480/360 → VP9 独立 480/360
 → 对应已合并四档
 → AVC1 独立/已合并 480/360
 → b[height<=720] + 音频
```

过滤器示例：

```powershell
bv*[vcodec^=av01][height<=720][height>480][fps<=30][dynamic_range!*=HDR]
bv*[vcodec^=av01][height<=480][height>=360][fps<=30][dynamic_range!*=HDR]
```

### 4.3 Generic（其它站）【新增】

在 Movie/Phonics 类似编码偏好之外，增加：

```text
bv*[height<=MaxHeight] + 音频
b[height<=MaxHeight] + 音频
b + 音频
```

无 AV1/VP9 的站点会落到 height / `b` 兜底。

---

## 5. 音频选择（query-youtube.ps1 / query-generic.ps1）

**优先级：**

1. 纯 Opus（`acodec` 以 opus 开头且 `vcodec=none`）
2. 若无 Opus → 纯 AAC / m4a（`mp4a*` / `aac*` 且 `vcodec=none`）
3. （generic）仍无 → 任意纯音轨（`vcodec=none`）
4. 仍无独立音轨 → selection 文件写空，主脚本使用 `ba*` 回退

**其它规则（YouTube）：**
1. xtags 判断 ORIGINAL / DUBBED / DUBBED-AUTO / UNKNOWN
2. **排除 DUBBED-AUTO**
3. 按 Source+Language 分组，优先无 DRC → 高 abr → 高 asr
4. 写入 `SOURCE|lang|format_id`；无 Opus 则 `ba*`

**selection 文件：**

- 无论是否选中音轨，都用  
  `Set-Content -LiteralPath $SelectionFile -Value $Lines -Encoding UTF8`  
  写出（空数组也会生成空文件）
- 避免旧写法 `$Lines | Set-Content ...` 在空数组时不创建文件，导致  
  `ERROR: Selection file not found`

**多语言：**

| 情况 | 行为 |
|------|------|
| 有 Opus（或 AAC）多语言独立轨 | 仍按语言分组多选，配合 `--audio-multistreams` 多轨下载 |
| 仅 `ba*` 回退 | 通常只有 1 条“最佳音频” |

查询参数含：

```text
--dump-single-json
--ignore-no-formats-error    # 避免默认选格式失败导致 query 中断
--extractor-args "youtube:..."   # 仅 YouTube；generic 非 YT 不加
```

---

## 6. 字幕与清理

**config_youtube / config_generic：** `--write-subs --sub-langs all --sub-format vtt/best --embed-subs`

| 步骤 | 作用 |
|------|------|
| STEP 5 | 嵌入 en-orig（English auto-generated）；无则跳过 |
| STEP 6 | 按 info.json 写字幕轨 title |
| CLEANUP | 删除同名 .webp/.jpg/.png/.vtt/.srt/.description |

CLEANUP 使用目录枚举 + **LiteralPath**，避免标题中 `[Chinese Dubbed]` 等方括号导致删不掉缩略图。

**ffmpeg 与 PowerShell：【新增】**  
若 `$ErrorActionPreference = "Stop"`，ffmpeg 打到 **stderr** 的版本信息在 **Windows PowerShell 5.1** 上可能触发 `NativeCommandError`。  
- 建议下载用 **PowerShell 7（pwsh）**  
- 或在调用处临时 `Continue` + `-hide_banner -loglevel error` + `2>&1 | Out-Null`（generic 脚本已做）

---

## 7. 已完成跳过

| 场景 | 规则 |
|------|------|
| Playlist（有序号） | 仅当存在 `003 - *.mkv` 这类**当前序号前缀**文件时跳过 |
| 单视频 | 该标题目录内已有成品则跳过 |

- **YouTube：** 通常为 `.mkv`
- **Generic：** `.mkv` / `.mp4` / `.webm` 均视为已完成

避免「文件夹里已有一集 mkv 导致整表全跳过」。

---

## 8. Playlist 统计

```text
Succeeded / Failed + DETAILED RESULTS（INDEX / STATUS / ID / TITLE）
```

`-PlaylistIndexRange` 未选中的条目不计入。

---

## 9. 脚本参数

| 参数 | 说明 | 默认 |
|------|------|------|
| `Url` | 视频 / playlist / 频道 URL | 必填 |
| `Mode` | Movie / Phonics | Movie |
| `PlaylistIndexRange` | 指定序号 | 空 |
| `MaxHeight` | Movie 最高分辨率 | 0 → 询问 |
| `PreferCodec` | av01 / vp9 / avc1 | 空 → 询问 |
| `PlaylistTitle` / `PlaylistIndex` | 内部递归用 | 一般不手填 |
| `Adult`（仅 generic） | 保存到 `D:\03 Media\Adult` | 关；可交互选 Y |

---

## 10. config_youtube 要点

```text
--remote-components ejs:github
--extractor-args "youtube:player_client=default,web_embedded;skip=translated_subs"
--audio-multistreams
--merge-output-format mkv
--write-subs --sub-langs "all" --sub-format "vtt/best" --embed-subs
--write-thumbnail --embed-thumbnail --embed-chapters --embed-metadata
--continue --ignore-errors
--sleep-interval 5 --max-sleep-interval 10
```

**config_generic：** 与上类似，但 **不含** youtube `extractor-args`（避免非 YouTube 站点异常）。

---

## 11. VIDEO FORMAT SUMMARY 列

ID / CODEC / RESOLUTION / FPS / **VBR** / **SIZE** / **HDR** / TYPE  
（仅显示，不参与选择）

---

## 12. 常用命令

```powershell
# 查询在线视频
# 在线格式
.\yt-dlp.exe -F --cookies cookies.txt --remote-components ejs:github --extractor-args "youtube:player_client=default,web_embedded" "URL"

# 查询在线视频编码及字幕
.\yt-dlp.exe -F --cookies cookies.txt --remote-components ejs:github --extractor-args "youtube:player_client=default,web_embedded" "URL"; .\yt-dlp.exe --list-subs --sub-langs "en.*,zh.*" --cookies cookies.txt --remote-components ejs:github --extractor-args "youtube:player_client=default,web_embedded" "URL"

# 仅查询（YouTube）
.\query-youtube.ps1 "URL" -Mode Phonics

# 仅查询（generic）
.\query-generic.ps1 "URL" -Mode Movie

# 字幕列表
.\yt-dlp.exe --list-subs --sub-langs "en.*,zh.*" --cookies cookies.txt --remote-components ejs:github --extractor-args "youtube:player_client=default,web_embedded" "URL"

# 查看本地流信息
# 本地字幕轨
.\ffprobe -v error -select_streams s -show_entries stream_tags=language,title -of csv=p=0 "完整路径\文件.mkv"

# 视频流（请用 csv；ffprobe 官方无 table 输出格式）
& "D:\yt-dlp\ffprobe.exe" -v error -select_streams v -show_entries stream=index,codec_name,width,height,r_frame_rate,bit_rate -of table "你的文件名.mkv"

# 查询音频格式、声道、采样率、码率和语言
& "D:\yt-dlp\ffprobe.exe" -v error -select_streams a -show_entries "stream=index,codec_name,channels,sample_rate,bit_rate:stream_tags=language,title" -of table "你的文件名.mkv"

# 查询内嵌字幕的格式、语言和名称
& "D:\yt-dlp\ffprobe.exe" -v error -select_streams s -show_entries "stream=index,codec_name:stream_tags=language,title,handler_name" -of default=noprint_wrappers=1 "你的文件名.mkv"

# 查看全部流信息
& "D:\yt-dlp\ffprobe.exe" -v error -show_entries "stream=index,codec_type,codec_name,width,height,r_frame_rate,bit_rate,channels,sample_rate:stream_tags=language,title,handler_name" -of table "你的文件名.mkv"

# 查询本地目录下所有视频编码及字母信息
"════════════════════════════════════════════════════════════════════════════════════════════════";"FILE                          SIZE     CONT   VIDEO RES   FPS  VBR      AUDIO                         SUB";"════════════════════════════════════════════════════════════════════════════════════════════════";Get-ChildItem "D:\03 Media\Movies & TV\Single Files\2022-04-25\*.*" | Where-Object {$_.Extension -in ".mp4",".mkv",".webm"} | Sort Name | ForEach-Object {$v=&"D:\yt-dlp\ffprobe.exe" -v error -select_streams v:0 -show_entries "stream=codec_name,height,r_frame_rate,bit_rate" -of csv=p=0 $_.FullName;$a=&"D:\yt-dlp\ffprobe.exe" -v error -select_streams a -show_entries "stream=codec_name,bit_rate:stream_tags=language" -of csv=p=0 $_.FullName;$s=&"D:\yt-dlp\ffprobe.exe" -v error -select_streams s -show_entries "stream_tags=language" -of csv=p=0 $_.FullName;$v=$v -split ',';$video=$v[0].ToUpper();$res=$v[1]+"p";$fps=if($v[2]-match "/"){[math]::Round(($v[2]-split'/')[0]/($v[2]-split'/')[1])}else{"?"};$vbr=if($v[3]-match '^\d+$'){([math]::Round([int]$v[3]/1000)).ToString()+"k"}else{"N/A"};$aud=if(!$a){"-"}else{($a|ForEach-Object{$x=$_-split ',';$abr=if($x[1]-match '^\d+$'){([math]::Round([int]$x[1]/1000)).ToString()+"k"}else{"N/A"};$lang=if($x.Count -gt 2 -and $x[2]){$x[2]}else{"und"};"$($x[0].ToUpper()) $abr $lang"})-join ";"};$sub=if(!$s){"-"}else{($s -join ",").ToUpper()};$size=[math]::Round($_.Length/1MB,1);"{0,-30}{1,-8}{2,-6}{3,-6}{4,-6}{5,-5}{6,-8}{7,-30}{8}" -f $_.Name,$($size.ToString()+"MB"),$_.Extension.Trim('.').ToUpper(),$video,$res,$fps,$vbr,$aud,$sub};"════════════════════════════════════════════════════════════════════════════════════════════════"

# 表格窗口显示本地文件信息
$dir="D:\10 Learning\English\Phonics"; Get-ChildItem -LiteralPath $dir -File -Recurse | Where-Object {$_.Extension -in ".mkv",".mp4",".webm"} | Sort-Object FullName | ForEach-Object {$f=$_.FullName; $v=&"D:\yt-dlp\ffprobe.exe" -v error -select_streams v:0 -show_entries "stream=codec_name,height,r_frame_rate,bit_rate" -of csv=p=0 $f 2>$null; $ct=&"D:\yt-dlp\ffprobe.exe" -v error -select_streams v:0 -show_entries stream=color_transfer -of csv=p=0 $f 2>$null; $a=&"D:\yt-dlp\ffprobe.exe" -v error -select_streams a -show_entries "stream=codec_name,bit_rate:stream_tags=language" -of csv=p=0 $f 2>$null; $s=&"D:\yt-dlp\ffprobe.exe" -v error -select_streams s -show_entries stream_tags=language -of csv=p=0 $f 2>$null; $vp=if($v){$v -split ','}else{@("-","-","-","-")}; $video=if($vp[0]){$vp[0].ToUpper()}else{"-"}; $res=if($vp[1] -match '^\d+$'){"$($vp[1])p"}else{"-"}; $fps=if($vp[2] -match "/"){$p=$vp[2] -split "/";[math]::Round([double]$p[0]/[double]$p[1],2)}else{"?"}; $vbr=if($vp[3] -match '^\d+$'){"{0}k" -f [math]::Round([int]$vp[3]/1000)}else{"N/A"}; $hdr=if($ct -match "smpte2084|arib-std-b67|smpte428"){"HDR"}elseif($ct -match "bt709|bt470|smpte170m|iec61966"){"SDR"}elseif([string]::IsNullOrWhiteSpace($ct)){"-"}else{$ct}; $aud=if(-not $a){"-"}else{($a|ForEach-Object{$x=$_-split ",";$abr=if($x[1]-match '^\d+$'){"{0}k" -f [math]::Round([int]$x[1]/1000)}else{"N/A"};$lang=if($x.Count -gt 2 -and $x[2]){$x[2]}else{"und"};"$($x[0].ToUpper()) $abr $lang"})-join "; "}; $sub=if(-not $s){"-"}else{(($s|Where-Object{$_})-join ",").ToUpper()}; $idx=if($_.BaseName -match '^\s*(\d+)'){$Matches[1]}else{"-"}; [PSCustomObject]@{IDX=$idx; FOLDER=$_.Directory.Name; FILE=$_.Name; SIZE=("{0:N1} MB" -f ($_.Length/1MB)); CONT=$_.Extension.Trim(".").ToUpper(); VIDEO=$video; RES=$res; FPS=$fps; VBR=$vbr; HDR=$hdr; AUDIO=$aud; SUB=$sub}} | Out-GridView -Title "Media scan"


# 脚本语法检查
$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("D:\yt-dlp\query-JSON-v4.ps1",[ref]$tokens,[ref]$errors) | Out-Null; $errors | ForEach-Object { "Line $($_.Extent.StartLineNumber), Col $($_.Extent.StartColumnNumber): $($_.Message)" }
没有任何输出：语法检查通过。

# 备份脚本命令
PS D:\yt-dlp> copy-Item "D:\yt-dlp\youtube\query-youtube.ps1" "D:\yt-dlp\youtube\query-youtube-20261028-正常版.ps1"
PS D:\yt-dlp> copy-Item "D:\yt-dlp\youtube\download-youtube.ps1" "D:\yt-dlp\youtube\download-youtube-20261028-正常版.ps1"


# 本地视频查询脚本的使用方法：
PowerShell# 默认目录
D:\yt-dlp\scan-media.ps1

# 指定目录
D:\yt-dlp\scan-media.ps1 "D:\03 Media\Movies & TV\Playlist"
窗口里可拖宽列、点表头排序；CONT、SUB、完整文件名都不会截断。

# 封装字幕
.\ffmpeg -i "How to describe different sizes in English.mp4" -i "How to describe different sizes in English [QpEGDf3WAn8].es-US.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].en-orig.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].pt-BR.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].ja.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].it.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].id.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].hi.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].de-DE.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].fr-FR.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].en.srt" -i "How to describe different sizes in English [QpEGDf3WAn8].zh-Hans.srt" -map 0 -map 1 -map 2 -map 3 -map 4 -map 5 -map 6 -map 7 -map 8 -map 9 -map 10 -map 11 -c copy -metadata:s:s:0 language=es-US -metadata:s:s:1 language=en-orig -metadata:s:s:2 language=pt-BR -metadata:s:s:3 language=ja -metadata:s:s:4 language=it -metadata:s:s:5 language=id -metadata:s:s:6 language=hi -metadata:s:s:7 language=de-DE -metadata:s:s:8 language=fr-FR -metadata:s:s:9 language=en -metadata:s:s:10 language=zh-Hans "How to describe different sizes in English sub.mp4"


# yt-dlp原生命令
下载普通 YouTube 视频：
.\yt-dlp.exe --config-location "D:\yt-dlp\config_phonics Minimum AVC1 480P" "https://www.youtube.com/watch?v=XlxEE41JHK4"

.\yt-dlp.exe --config-location "D:\yt-dlp\config_phonics Minimum AVC1 480P" "https://www.youtube.com/watch?v=aftne3KaXEM"

如果是 Playlist：
.\yt-dlp.exe --config-location "D:\yt-dlp\config_phonics Minimum AVC1 480P" "https://www.youtube.com/playlist?list=XXXXXXXXXXX"


如果需要 cookies
.\yt-dlp.exe --ignore-config --cookies cookies.txt --config-location "D:\yt-dlp\config_phonics AVC1 + Opus" "https://www.youtube.com/watch?v=QpEGDf3WAn8" -o ""



如果是 Playlist：
.\yt-dlp.exe --cookies cookies.txt --config-location "D:\yt-dlp\config_phonics" "https://www.youtube.com/playlist?list=PLToJJ2R3kEHqDaSE5GxLX2JgkXo0EzO3E&index=1"


```
---

## 13. GitHub 同步（简要）

- 仓库示例：`https://github.com/Bob-maxb/yt-dlp-scripts`
- **不要**提交 `cookies.txt`、exe、视频文件（用 `.gitignore`）
- 更新后：

```powershell
cd D:\yt-dlp\yt-dlp-git
git add .
git commit -m "说明改动"
git push
```

---

## 14. 故障排查

| 现象 | 处理 |
|------|------|
| query 报 Requested format is not available | 查询加 `--ignore-no-formats-error` |
| 480p 抢在 720p 前 | 使用 height 分档（>480 / >=360） |
| Playlist 一集存在就全跳过 | 按 `003 -` 前缀匹配 |
| 残留 .webp | CLEANUP 用 LiteralPath；标题含 `[]` 时旧逻辑会失败 |
| 找不到 download-*.ps1 | 在脚本实际目录执行，或写全路径 |
| git 不是内部或外部命令 | 安装 Git for Windows 并重开终端 |
| push 前 Author identity unknown | `git config --global user.name` / `user.email` |
| Selection file not found（无 Opus 老视频） | 用 `Set-Content -Value $Lines`；可加 AAC 兜底 |
| 只有 AAC、没有 Opus | 先选 AAC 纯音轨，否则 `ba*` |
| ffmpeg version … NativeCommandError | PS 5.1 + Stop 把 stderr 当错误；用 pwsh 7 或静默调用 ffmpeg |
| 脚本 not digitally signed / cannot be loaded | 见 §14.1 |

### 14.1 PowerShell 执行策略【新增】

查看：

```powershell
Get-ExecutionPolicy -List
```

常见：`LocalMachine = RemoteSigned`（本机脚本可跑；**从网络保存的文件**需解锁或签名）。

**解除“来自网络”标记（推荐，含子目录）：**

```powershell
Get-ChildItem "D:\yt-dlp" -Recurse -File | Unblock-File
```

- `-Recurse`：进入 `youtube`、`generic` 等子文件夹  
- `-File`：只处理文件  

**仅当前窗口临时允许：**

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

关闭窗口后失效。

| 命令 | 含义 |
|------|------|
| `LocalMachine RemoteSigned` | 全机：本地可跑，外来需签名/解锁 |
| `CurrentUser RemoteSigned` | 仅当前用户 |
| `Process Bypass` | 仅本窗口 |

给脚本末尾加空行**不能**解除策略限制。

---

## 15. 设计原则

1. 容器 MKV；音频 Opus；字幕 VTT 嵌入  
2. Phonics：≤30fps、偏 720/480、排除 HDR  
3. Movie：可交互分辨率/编码；Playlist 只问一次  
4. 选择顺序：独立高 → 独立次 → 合并高 → 合并次 → AVC1 → 兜底  
5. 已完成可安全重跑；特殊字符文件名可清理  
6. YouTube / Generic 分目录；exe 与 cookies 固定在 `D:\yt-dlp\`  
7. 未指定 `-Mode` 时交互选择；Generic 可再选 Adult 根目录  

---

## 16. 补充

- 体积粗算：`MiB ≈ 总码率(kbps) × 秒 / 8388.608`  
- 优选实测：视频 + Opus + MKV + VTT  
- 可选关机：`shutdown /s /t 60`（取消：`shutdown /a`）

---

## 17. 脚本职责

| 文件 | 职责 |
|------|------|
| `download-youtube.ps1` | 链接解析、Playlist/频道、格式选择、下载、后处理、跳过、统计 |
| `query-youtube.ps1` | 查询 JSON、目录、音频选择、格式/字幕摘要 |
| `config_youtube` | yt-dlp 全局参数（含 youtube extractor-args） |
| `download-generic.ps1` | 其它站点下载（对齐主流程） |
| `query-generic.ps1` | 其它站点查询（upload_date 可回退） |
| `config_generic` | 通用配置（无 youtube extractor-args） |

---

## 18. Appendy
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




### 音频 -F 重点字段

在 -F 输出里，你以后重点看这些：

字段	含义	对我们有多重要
format_id	音频格式 ID	⭐⭐⭐⭐⭐
language	音频语言代码	⭐⭐⭐⭐⭐
acodec	音频编码器	⭐⭐⭐⭐⭐
abr	平均音频码率	⭐⭐⭐⭐⭐
audio_channels	声道数	⭐⭐⭐⭐
asr	采样率 Hz	⭐⭐⭐⭐
format_note	YouTube 提供的附加说明	⭐⭐⭐⭐⭐
aext	音频扩展名/容器	⭐⭐⭐
protocol	下载协议	⭐⭐⭐
filesize	文件大小	⭐⭐
quality	yt-dlp 的质量排序字段	⭐⭐⭐
lang	yt-dlp 的语言偏好排序字段	⭐⭐⭐⭐


| 参数 | 作用 |
|------|------|
| -F / --list-formats | 列出格式 | 人查看 | 
| -f | 选择格式下载 |
| -J / --dump-json | 完整 JSON | 程序分析 | 
| --write-info-json | 保存 JSON | 以后离线分析 | 

## 19. 文件重命名备忘【新增】

| 旧名 | 新名 |
|------|------|
| download-movie.ps1 | download-youtube.ps1 |
| query-JSON-v4.ps1 | query-youtube.ps1 |
| config_movie | config_youtube |
| download-other.ps1 | download-generic.ps1 |
| query-other.ps1 | query-generic.ps1 |
| config_other | config_generic |

download 脚本内 `$Config`、`$QueryScript` 必须与**实际文件名**一致。

---

*文档结束（Complete v5）。脚本再变更时请同步修订本指南。*
