
param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$PlaylistTitle = "",

    [ValidateSet("Movie", "Phonics")]
    [string]$Mode = "Movie",


    [int]$PlaylistIndex = 0,

    [string]$PlaylistIndexRange = "",

    [int]$MaxHeight = 0,

    [string]$PreferCodec = ""
)


$ErrorActionPreference = "Stop"





# ========================================
# watch?v= + list= ：询问单集还是整表
# （递归下载单集时已带 PlaylistTitle，不会再问）
# ========================================
if (
    [string]::IsNullOrWhiteSpace($PlaylistTitle) -and
    $Url -match '(?i)youtube\.com/watch\?' -and
    $Url -match '(?i)[?&]list=([a-zA-Z0-9_-]+)'
) {
    $ListId = $Matches[1]

    $VideoId = $null
    if ($Url -match '(?i)[?&]v=([a-zA-Z0-9_-]+)') {
        $VideoId = $Matches[1]
    }

    Write-Host ""
    Write-Host "=== LINK CONTAINS VIDEO + PLAYLIST ===" -ForegroundColor Cyan
    Write-Host ""
    if ($VideoId) {
        Write-Host "Video    : $VideoId"
    }
    Write-Host "Playlist : $ListId"
    Write-Host ""
    Write-Host "  1 = Download this video only (默认)"
    Write-Host "  2 = Download entire playlist"
    Write-Host ""

    $LinkChoice = Read-Host "Select [1-2] (default 1)"
    if ([string]::IsNullOrWhiteSpace($LinkChoice)) { $LinkChoice = "1" }

    if ($LinkChoice -eq "2") {
        $Url = "https://www.youtube.com/playlist?list=$ListId"
        Write-Host "Mode     : Full playlist" -ForegroundColor Yellow
    }
    else {
        if ($VideoId) {
            $Url = "https://www.youtube.com/watch?v=$VideoId"
        }
        Write-Host "Mode     : Single video" -ForegroundColor Yellow
    }
    Write-Host ""
}






# ========================================
# 判断下载模式
# ========================================

if ($Url -match '(?i)(youtube\.com/playlist(?:\?|$)|youtube\.com/@[^/]+/videos(?:[?#]|$))') {

    # 直接传入 Playlist URL
    $PlaylistMode = $true
    $PlaylistTitle = ""

}
elseif (-not [string]::IsNullOrWhiteSpace($PlaylistTitle)) {

    # Playlist 内部的视频，由父进程显式传入 PlaylistTitle
    $PlaylistMode = $true

}
else {

    # 普通单视频
    $PlaylistMode = $false
    $PlaylistTitle = ""

}

# $YtDlp       = "D:\yt-dlp\yt-dlp.exe"
# $FFmpeg      = "D:\yt-dlp\ffmpeg.exe"
# $FFprobe     = "D:\yt-dlp\ffprobe.exe"
# $Config      = "D:\yt-dlp\config_movie"
# $QueryScript = "D:\yt-dlp\query-JSON-v4.ps1"
# $Cookies     = "D:\yt-dlp\cookies.txt"

$Root        = "D:\yt-dlp"
$YtDlp       = Join-Path $Root "yt-dlp.exe"
$FFmpeg      = Join-Path $Root "ffmpeg.exe"
$FFprobe     = Join-Path $Root "ffprobe.exe"
$Config      = Join-Path $PSScriptRoot "config_youtube"   # 和 ps1 同目录
$QueryScript = Join-Path $PSScriptRoot "query-youtube.ps1"
$Cookies     = Join-Path $Root "cookies.txt"

# Mode：命令行未指定 -Mode 时才询问（默认 Movie）
if (-not $PSBoundParameters.ContainsKey('Mode')) {
    Write-Host ""
    Write-Host "Download mode?" -ForegroundColor Cyan
    Write-Host "  1 = Movie   (default)  -> D:\03 Media\Movies & TV"
    Write-Host "  2 = Phonics            -> D:\10 Learning\English\Phonics"
    $ModeChoice = Read-Host "Select [1-2] (default 1)"
    if ($ModeChoice -eq "2") {
        $Mode = "Phonics"
        Write-Host "Mode: Phonics" -ForegroundColor Yellow
    }
    else {
        $Mode = "Movie"
        Write-Host "Mode: Movie" -ForegroundColor Yellow
    }
}

# $BaseDir = "D:\03 Media\Movies & TV"
# ========================================
# PLAYLIST MODE
# ========================================

if ($Url -match '(?i)(youtube\.com/playlist(?:\?|$)|youtube\.com/@[^/]+/videos(?:[?#]|$))') {

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " PLAYLIST MODE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "[1/3] Connecting to YouTube and reading playlist..."

    $PlaylistArgs = @(
        "--no-warnings"
        "--flat-playlist"
        "--dump-single-json"
        "--cookies", $Cookies
        "--remote-components", "ejs:github"
        "--extractor-args", "youtube:player_client=default,web_embedded;skip=translated_subs"
        $Url
    )

    Write-Host "[2/3] Loading playlist entries..."
    $PlaylistJsonText = & $YtDlp @PlaylistArgs 2>&1





    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: Playlist query failed." -ForegroundColor Red
        $PlaylistJsonText
        exit 1
    }

    $Start = $PlaylistJsonText.IndexOf("{")

    if ($Start -lt 0) {
        Write-Host ""
        Write-Host "ERROR: Playlist JSON not found." -ForegroundColor Red
        exit 1
    }

    $PlaylistJsonText = $PlaylistJsonText.Substring($Start)

    try {
        $PlaylistInfo = $PlaylistJsonText | ConvertFrom-Json
    }
    catch {
        Write-Host ""
        Write-Host "ERROR: Playlist JSON parse failed." -ForegroundColor Red
        exit 1
    }

    $PlaylistTitle = [string]$PlaylistInfo.title

    if ([string]::IsNullOrWhiteSpace($PlaylistTitle)) {
        Write-Host ""
        Write-Host "ERROR: Playlist title not found." -ForegroundColor Red
        exit 1
    }

    Write-Host "[3/3] Processing playlist information..."

    $Entries = @(
        $PlaylistInfo.entries |
        Where-Object {
            $_ -and (
                $_.id -or
                $_.url
            )
        }
    )

    if ($Entries.Count -eq 0) {
        Write-Host ""
        Write-Host "ERROR: No videos found in playlist." -ForegroundColor Red
        exit 1
    }

    Write-Host "Playlist      : $PlaylistTitle"
    Write-Host "Videos        : $($Entries.Count)"
    Write-Host ""






# 这里是前面已有的代码
# ...

# ========================================
# PLAYLIST INDEX RANGE
# 例如：
# 8-11
# 8,10
# 8-11,15,20-22
# ========================================

$SelectedIndexes = $null

if (-not [string]::IsNullOrWhiteSpace($PlaylistIndexRange)) {

    $SelectedIndexes = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($Part in ($PlaylistIndexRange -split ",")) {

        $Part = $Part.Trim()

        if ($Part -match '^\s*(\d+)\s*-\s*(\d+)\s*$') {

            $Start = [int]$Matches[1]
            $End   = [int]$Matches[2]

            if ($Start -gt $End) {
                $Temp  = $Start
                $Start = $End
                $End   = $Temp
            }

            for ($i = $Start; $i -le $End; $i++) {
                [void]$SelectedIndexes.Add($i)
            }
        }
        elseif ($Part -match '^\s*(\d+)\s*$') {

            [void]$SelectedIndexes.Add([int]$Part)
        }
        else {
            Write-Host "ERROR: Invalid PlaylistIndexRange: $Part" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host ""
    Write-Host "Selected playlist indexes: $((($SelectedIndexes | Sort-Object) -join ', '))" -ForegroundColor Cyan
}






# ========================================
# Playlist 级：Movie 只询问一次分辨率/编码
# ========================================
if ($Mode -eq "Movie" -and $MaxHeight -le 0) {

    Write-Host ""
    Write-Host "=== MOVIE FORMAT PREFERENCE (Playlist) ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Max resolution:"
    Write-Host "  1 = 2160 (4K)"
    Write-Host "  2 = 1440 (2K)"
    Write-Host "  3 = 1080 (默认)"
    Write-Host "  4 = 720"
    Write-Host ""

    $ResChoice = Read-Host "Select [1-4] (default 3)"
    if ([string]::IsNullOrWhiteSpace($ResChoice)) { $ResChoice = "3" }

    switch ($ResChoice) {
        "1" { $MaxHeight = 2160 }
        "2" { $MaxHeight = 1440 }
        "4" { $MaxHeight = 720 }
        default { $MaxHeight = 1080 }
    }

    Write-Host ""
    Write-Host "Preferred video codec:"
    Write-Host "  1 = AV1 优先 (默认)"
    Write-Host "  2 = VP9 优先"
    Write-Host "  3 = AVC1 优先"
    Write-Host ""

    $CodecChoice = Read-Host "Select [1-3] (default 1)"
    if ([string]::IsNullOrWhiteSpace($CodecChoice)) { $CodecChoice = "1" }

    switch ($CodecChoice) {
        "2" { $PreferCodec = "vp9" }
        "3" { $PreferCodec = "avc1" }
        default { $PreferCodec = "av01" }
    }

    Write-Host ""
    Write-Host "Playlist will use : max ${MaxHeight}p | prefer $PreferCodec" -ForegroundColor Yellow
    Write-Host ""
}













$SuccessCount = 0
$FailCount    = 0
$Results      = @()


    $Index = 0
    foreach ($Entry in $Entries) {

        $Index++



    if ($null -ne $SelectedIndexes -and -not $SelectedIndexes.Contains($Index)) {
        continue
    }




        if ($Entry.webpage_url) {
            $VideoUrl = [string]$Entry.webpage_url
        }
        elseif ($Entry.url -match '^https?://') {
            $VideoUrl = [string]$Entry.url
        }
        else {
            $VideoUrl = "https://www.youtube.com/watch?v=$($Entry.id)"
        }

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " PLAYLIST ITEM $Index / $($Entries.Count)" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        Write-Host "URL: $VideoUrl"

        & $PSCommandPath $VideoUrl `
            -PlaylistTitle $PlaylistTitle `
            -Mode $Mode `
            -PlaylistIndex $Index `
            -MaxHeight $MaxHeight `
            -PreferCodec $PreferCodec

        $ItemExitCode = $LASTEXITCODE

        $VideoTitle = if ($Entry.title) { [string]$Entry.title } else { $Entry.id }
        $VideoId    = [string]$Entry.id

        if ($ItemExitCode -eq 0) {
            $SuccessCount++
            $Status = "OK"
        }
        else {
            $FailCount++
            $Status = "FAILED"

            Write-Host ""
            Write-Host "WARNING: Playlist item failed." -ForegroundColor Yellow
            Write-Host "Continuing to next item..."
        }

        $Results += [PSCustomObject]@{
            Index  = $Index
            Id     = $VideoId
            Title  = $VideoTitle
            Status = $Status
        }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " PLAYLIST COMPLETE" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Playlist      : $PlaylistTitle"
    Write-Host "Total items   : $($Results.Count)"
    Write-Host "Succeeded     : $SuccessCount" -ForegroundColor Green
    Write-Host "Failed        : $FailCount" -ForegroundColor $(if ($FailCount -gt 0) { "Red" } else { "Green" })
    Write-Host ""

    if ($Results.Count -gt 0) {
        Write-Host "=== DETAILED RESULTS ===" -ForegroundColor Cyan
        $Results | Format-Table -AutoSize `
            @{Label="INDEX";  Expression={$_.Index};  Width=6},
            @{Label="STATUS"; Expression={$_.Status}; Width=8},
            @{Label="ID";     Expression={$_.Id};     Width=12},
            @{Label="TITLE";  Expression={$_.Title}} |
            Out-Host
    }

    Write-Host ""
    exit 0

}

# ============================================================
# FORMAT SIZE
# ============================================================

function Format-Size {
    param(
        [double]$Bytes
    )

    if ($Bytes -le 0) {
        return "-"
    }

    if ($Bytes -ge 1GB) {
        return "{0:N2} GiB" -f ($Bytes / 1GB)
    }

    return "{0:N2} MiB" -f ($Bytes / 1MB)
}


# ============================================================
# FORMAT NUMBER
# ============================================================

function Format-Number {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return "-"
    }

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return "-"
    }

    try {
        return "{0:N2}" -f ([double]$Value)
    }
    catch {
        return [string]$Value
    }
}


# ============================================================
# STEP 5
# 添加 English auto-generated subtitle
# 直接使用 STEP 1 保存的 info.json
# 不重新调用 yt-dlp
# ============================================================

function Add-EnglishAutoSubtitle {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Mkv,

        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    $base = [System.IO.Path]::ChangeExtension($Mkv, $null)
    $base = $base.TrimEnd('.')

    $vtt = "$base.en-orig.vtt"
    $tmp = "$base.auto-vtt.mkv"

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " STEP 5 - ENGLISH AUTO SUBTITLE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # ========================================
    # 检查 info.json
    # ========================================

    if (-not (Test-Path -LiteralPath $Json)) {
        Write-Host "English auto subtitle : info.json not found" -ForegroundColor Yellow
        Write-Host "Subtitle added        : No" -ForegroundColor Yellow
        return
    }

    try {
        $Info = Get-Content `
            -LiteralPath $Json `
            -Raw `
            -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        Write-Host "English auto subtitle : Failed to read info.json" -ForegroundColor Red
        Write-Host "Subtitle added        : No" -ForegroundColor Red
        return
    }

    # ========================================
    # 查找 English auto-generated
    # ========================================

    $AutoCaption = $Info.automatic_captions.'en-orig'

    if ($null -eq $AutoCaption) {
        Write-Host "English auto subtitle : Not found" -ForegroundColor Yellow
        Write-Host "Subtitle added        : No" -ForegroundColor Yellow
        return
    }

    $SubtitleEntry = @(
        $AutoCaption |
        Where-Object {
            $_.url -and $_.ext -eq "vtt"
        }
    ) |
    Select-Object -First 1

    if ($null -eq $SubtitleEntry) {
        Write-Host "English auto subtitle : No usable VTT" -ForegroundColor Yellow
        Write-Host "Subtitle added        : No" -ForegroundColor Yellow
        return
    }

    $SubtitleUrl = [string]$SubtitleEntry.url

    if ([string]::IsNullOrWhiteSpace($SubtitleUrl)) {
        Write-Host "English auto subtitle : URL empty" -ForegroundColor Yellow
        Write-Host "Subtitle added        : No" -ForegroundColor Yellow
        return
    }

    Write-Host "English auto subtitle : Found" -ForegroundColor Green

    # ========================================
    # 下载 VTT
    # ========================================

    try {

        Invoke-WebRequest `
            -Uri $SubtitleUrl `
            -OutFile $vtt `
            -UseBasicParsing `
            *> $null

    }
    catch {

        Write-Host "Subtitle download     : Failed" -ForegroundColor Red
        Write-Host "Subtitle added        : No" -ForegroundColor Red

        Remove-Item `
            -LiteralPath $vtt `
            -Force `
            -ErrorAction SilentlyContinue

        return
    }

    if (-not (Test-Path -LiteralPath $vtt)) {
        Write-Host "Subtitle download     : Failed" -ForegroundColor Red
        Write-Host "Subtitle added        : No" -ForegroundColor Red
        return
    }

    Write-Host "Subtitle download     : OK" -ForegroundColor Green

    # ========================================
    # 获取现有字幕轨数量
    # ========================================

    $SubtitleCount = @(
        & $FFprobe -v error `
            -select_streams s `
            -show_entries stream=index `
            -of csv=p=0 `
            $Mkv 2>$null
    ).Count

    # ========================================
    # 嵌入 English auto subtitle
    # ========================================

    & $FFmpeg `
        -y `
        -i $Mkv `
        -i $vtt `
        -map 0 `
        -map 1:0 `
        -c copy `
        -metadata:s:s:$SubtitleCount language=eng `
        -metadata:s:s:$SubtitleCount title="English (auto-generated)" `
        $tmp `
        *> $null

    if ($LASTEXITCODE -ne 0) {

        Write-Host "Subtitle embedding    : Failed" -ForegroundColor Red
        Write-Host "Subtitle added        : No" -ForegroundColor Red

        Remove-Item `
            -LiteralPath $tmp `
            -Force `
            -ErrorAction SilentlyContinue

        throw "English auto-generated subtitle embedding failed."
    }

    Move-Item `
        -LiteralPath $tmp `
        -Destination $Mkv `
        -Force

    Write-Host "Subtitle embedding    : OK" -ForegroundColor Green
    Write-Host "Subtitle added        : Yes" -ForegroundColor Green
}

# ============================================================
# STEP 6
# 根据 info.json 的 name 给 MKV 字幕轨道添加 title
# ============================================================

function Set-SubtitleTitles {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Mkv,

        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    $tmp = [System.IO.Path]::ChangeExtension($Mkv, ".title.mkv")



    if (-not (Test-Path -LiteralPath $Json)) {
        Write-Host "Subtitle titles  : info.json not found" -ForegroundColor Yellow
        return
    }

    try {
        $j = Get-Content `
            -LiteralPath $Json `
            -Raw `
            -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        Write-Host "Subtitle titles  : Failed to read info.json" -ForegroundColor Red
        return
    }

    $names = @(
        $j.subtitles.PSObject.Properties |
        ForEach-Object {
            ($_.Value | Select-Object -First 1).name
        }
    )

    $count = @(
        & $FFprobe -v error `
            -select_streams s `
            -show_entries stream=index `
            -of csv=p=0 `
            $Mkv 2>$null
    ).Count

    if ($count -eq 0) {
        Write-Host "Subtitle streams : 0" -ForegroundColor Yellow
        Write-Host "Subtitle titles  : None"
        return
    }

    $args = @(
        "-y",
        "-i", $Mkv,
        "-map", "0",
        "-c", "copy"
    )

    $UpdatedCount = 0

    for ($i = 0; $i -lt $count; $i++) {

        if ($i -lt $names.Count -and $names[$i]) {

            $title = [string]$names[$i]

            $args += "-metadata:s:s:$i"
            $args += "title=$title"

            $UpdatedCount++
        }
    }

    & $FFmpeg @args $tmp *> $null

    if ($LASTEXITCODE -ne 0) {

        Write-Host "Subtitle streams : $count" 
        Write-Host "Subtitle titles  : Failed" -ForegroundColor Red

        if (Test-Path -LiteralPath $tmp) {
            Remove-Item `
                -LiteralPath $tmp `
                -Force `
                -ErrorAction SilentlyContinue
        }

        throw "Subtitle title update failed."
    }

    Move-Item `
        -LiteralPath $tmp `
        -Destination $Mkv `
        -Force

    Write-Host "Subtitle streams : $count"
    Write-Host "Subtitle titles  : Updated ($UpdatedCount)"
}

# ============================================================
# CLEANUP
# 所有后处理完成以后才清理临时文件
# ============================================================

function Remove-TemporaryFiles {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Mkv
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " CLEANUP" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $dir  = [System.IO.Path]::GetDirectoryName($Mkv)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Mkv)
    $mkvName = [System.IO.Path]::GetFileName($Mkv)

    # 用 LiteralPath + 按文件名匹配，避免标题中的 [] 被当成通配符
    $candidates = Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ne $mkvName -and (
                $_.BaseName -eq $name -or
                $_.Name.StartsWith($name + ".")
            )
        }

    foreach ($f in $candidates) {
        $ext = $f.Extension.ToLowerInvariant()
        $isTemp =
            $ext -in @(".webp", ".jpg", ".png", ".vtt", ".srt") -or
            $f.Name.EndsWith(".description")

        if ($isTemp) {
            Write-Host "[Cleanup] $($f.Name)"
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}


# ============================================================
# FINAL SUMMARY
# ============================================================

function Show-FinalSummary {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Mkv,

        [Parameter(Mandatory = $true)]
        [string]$Json,

        [Parameter(Mandatory = $true)]
        [string]$SelectionFile,

        [string]$SelectedVideoFormat
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " FINAL SUMMARY" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""

    # --------------------------------------------------------
    # 文件
    # --------------------------------------------------------

    $FileInfo = Get-Item -LiteralPath $Mkv

    Write-Host "FILE" -ForegroundColor Cyan
    Write-Host "Name       : $($FileInfo.Name)"
    Write-Host "Size       : $(Format-Size $FileInfo.Length)"
    Write-Host ""

    # --------------------------------------------------------
    # 读取 info.json
    # --------------------------------------------------------

    $Info = $null

    if (Test-Path -LiteralPath $Json) {

        try {
            $Info = Get-Content `
                -LiteralPath $Json `
                -Raw `
                -Encoding UTF8 |
                ConvertFrom-Json
        }
        catch {
            Write-Host "[Summary] Cannot read info.json" -ForegroundColor Yellow
        }
    }

    # --------------------------------------------------------
    # Selected audio
    # --------------------------------------------------------

    $SelectedAudioIds = @()

    if (Test-Path -LiteralPath $SelectionFile) {

        $SelectionLines = Get-Content `
            -LiteralPath $SelectionFile `
            -Encoding UTF8

        foreach ($Line in $SelectionLines) {

            if ([string]::IsNullOrWhiteSpace($Line)) {
                continue
            }

            $Parts = $Line -split "\|"

            if ($Parts.Count -ge 3) {

                $SelectedAudioIds += [string]$Parts[2]
            }
        }
    }

    $SelectedAudioIds = @(
        $SelectedAudioIds |
        Select-Object -Unique
    )

    # --------------------------------------------------------
    # SELECTED FORMAT
    # --------------------------------------------------------

    Write-Host "SELECTED FORMAT" -ForegroundColor Cyan

    if ([string]::IsNullOrWhiteSpace($SelectedVideoFormat)) {
        Write-Host "Video      : -"
    }
    else {
        Write-Host "Video      : $SelectedVideoFormat"
    }

    if ($SelectedAudioIds.Count -eq 0) {
        Write-Host "Audio      : fallback"
    }
    else {
        Write-Host "Audio      : $($SelectedAudioIds -join ' + ')"
    }

    Write-Host ""

    # --------------------------------------------------------
    # SOURCE FORMAT INFORMATION
    # --------------------------------------------------------

    if ($null -ne $Info) {

        Write-Host "SOURCE FORMAT" -ForegroundColor Cyan

        # Video
        if (-not [string]::IsNullOrWhiteSpace($SelectedVideoFormat)) {

            $SourceVideo = @(
                $Info.formats |
                Where-Object {
                    [string]$_.format_id -eq $SelectedVideoFormat
                }
            ) |
            Select-Object -First 1

            if ($null -ne $SourceVideo) {

                $VideoCodec = [string]$SourceVideo.vcodec

                $VideoResolution = "-"

                if ($SourceVideo.width -and $SourceVideo.height) {
                    $VideoResolution = "$($SourceVideo.width)x$($SourceVideo.height)"
                }

                $VideoFps = "-"
                if ($SourceVideo.fps) {
                    $VideoFps = "$($SourceVideo.fps) fps"
                }

                $VideoVbr = "-"
                if ($SourceVideo.vbr) {
                    $VideoVbr = "$(Format-Number $SourceVideo.vbr) kbps"
                }

                $VideoSize = "-"
                if ($SourceVideo.filesize) {
                    $VideoSize = Format-Size $SourceVideo.filesize
                }
                elseif ($SourceVideo.filesize_approx) {
                    $VideoSize = "~$(Format-Size $SourceVideo.filesize_approx)"
                }

                $VideoProtocol = [string]$SourceVideo.protocol

                Write-Host ""
                Write-Host "Video format : $($SourceVideo.format_id)"
                Write-Host "Codec        : $VideoCodec"
                Write-Host "Resolution   : $VideoResolution"
                Write-Host "FPS          : $VideoFps"
                Write-Host "VBR          : $VideoVbr"
                Write-Host "Size         : $VideoSize"
                Write-Host "Protocol     : $VideoProtocol"
            }
        }

        # Audio
        foreach ($AudioId in $SelectedAudioIds) {

            $SourceAudio = @(
                $Info.formats |
                Where-Object {
                    [string]$_.format_id -eq $AudioId
                }
            ) |
            Select-Object -First 1

            if ($null -eq $SourceAudio) {
                continue
            }

            $AudioCodec = [string]$SourceAudio.acodec

            $Language = [string]$SourceAudio.language
            if ([string]::IsNullOrWhiteSpace($Language)) {
                $Language = "-"
            }

            $Abr = "-"
            if ($SourceAudio.abr) {
                $Abr = "$(Format-Number $SourceAudio.abr) kbps"
            }

            $Asr = "-"
            if ($SourceAudio.asr) {
                $Asr = "$($SourceAudio.asr) Hz"
            }

            $AudioSize = "-"
            if ($SourceAudio.filesize) {
                $AudioSize = Format-Size $SourceAudio.filesize
            }
            elseif ($SourceAudio.filesize_approx) {
                $AudioSize = "~$(Format-Size $SourceAudio.filesize_approx)"
            }

            $AudioProtocol = [string]$SourceAudio.protocol

            Write-Host ""
            Write-Host "Audio format : $($SourceAudio.format_id)"
            Write-Host "Codec        : $AudioCodec"
            Write-Host "Language     : $Language"
            Write-Host "ABR          : $Abr"
            Write-Host "ASR          : $Asr"
            Write-Host "Size         : $AudioSize"
            Write-Host "Protocol     : $AudioProtocol"
        }
    }

    Write-Host ""

    # --------------------------------------------------------
    # FINAL MKV - ffprobe
    # --------------------------------------------------------

    Write-Host "FINAL MKV" -ForegroundColor Cyan

    $ProbeJson = & $FFprobe `
        -v error `
        -show_streams `
        -show_format `
        -of json `
        $Mkv

    if ($LASTEXITCODE -ne 0) {

        Write-Host "[Summary] ffprobe failed" -ForegroundColor Red
        return
    }

    try {
        $Probe = $ProbeJson | ConvertFrom-Json
    }
    catch {
        Write-Host "[Summary] Cannot parse ffprobe result" -ForegroundColor Red
        return
    }

    # --------------------------------------------------------
    # Final video streams
    # --------------------------------------------------------

    $FinalVideoStreams = @(
        $Probe.streams |
        Where-Object {
            $_.codec_type -eq "video"
        }
    )

    $VideoIndex = 1

    foreach ($V in $FinalVideoStreams) {

        $Resolution = "-"

        if ($V.width -and $V.height) {
            $Resolution = "$($V.width)x$($V.height)"
        }

        $FPS = "-"

        if ($V.r_frame_rate -and $V.r_frame_rate -ne "0/0") {

            try {
                $FPSValue = [double]$V.r_frame_rate.Split('/')[0] /
                            [double]$V.r_frame_rate.Split('/')[1]

                $FPS = "{0:N2} fps" -f $FPSValue
            }
            catch {}
        }

        $Bitrate = "-"
        if ($V.bit_rate) {
            $Bitrate = "{0:N0} kbps" -f ([double]$V.bit_rate / 1000)
        }

        Write-Host ""
        Write-Host "Video $VideoIndex"
        Write-Host "Codec        : $($V.codec_name)"
        Write-Host "Resolution   : $Resolution"
        Write-Host "FPS          : $FPS"
        Write-Host "Bitrate      : $Bitrate"

        $VideoIndex++
    }

    # --------------------------------------------------------
    # Final audio streams
    # --------------------------------------------------------

    $FinalAudioStreams = @(
        $Probe.streams |
        Where-Object {
            $_.codec_type -eq "audio"
        }
    )

    $AudioIndex = 1

    foreach ($A in $FinalAudioStreams) {

        $Language = "-"
        $Title = "-"

        if ($A.tags) {

            if ($A.tags.language) {
                $Language = [string]$A.tags.language
            }

            if ($A.tags.title) {
                $Title = [string]$A.tags.title
            }
        }

        $Bitrate = "-"
        if ($A.bit_rate) {
            $Bitrate = "{0:N0} kbps" -f ([double]$A.bit_rate / 1000)
        }

        $SampleRate = "-"
        if ($A.sample_rate) {
            $SampleRate = "$($A.sample_rate) Hz"
        }

        Write-Host ""
        Write-Host "Audio $AudioIndex"
        Write-Host "Codec        : $($A.codec_name)"
        Write-Host "Language     : $Language"
        Write-Host "Title        : $Title"
        Write-Host "Channels     : $($A.channels)"
        Write-Host "Sample rate  : $SampleRate"
        Write-Host "Bitrate      : $Bitrate"

        $AudioIndex++
    }

    # --------------------------------------------------------
    # Final subtitles
    # --------------------------------------------------------

    $FinalSubtitleStreams = @(
        $Probe.streams |
        Where-Object {
            $_.codec_type -eq "subtitle"
        }
    )

    Write-Host ""
    Write-Host "Subtitles    : $($FinalSubtitleStreams.Count)"

    $SubtitleIndex = 1

    foreach ($S in $FinalSubtitleStreams) {

        $Language = "-"
        $Title = "-"

        if ($S.tags) {

            if ($S.tags.language) {
                $Language = [string]$S.tags.language
            }

            if ($S.tags.title) {
                $Title = [string]$S.tags.title
            }
        }

        Write-Host "Subtitle $SubtitleIndex : $Language | $Title"

        $SubtitleIndex++
    }

    # --------------------------------------------------------
    # Final container
    # --------------------------------------------------------

    if ($Probe.format) {

        $ContainerSize = "-"

        if ($Probe.format.size) {
            $ContainerSize = Format-Size $Probe.format.size
        }

        Write-Host ""
        Write-Host "Container    : $($Probe.format.format_name)"
        Write-Host "Final size   : $ContainerSize"
    }

    Write-Host ""
}




# ============================================================
# STEP 1
# QUERY AUDIO
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

if ($PlaylistMode) {
    Write-Host " STEP 1 - QUERY AUDIO (PLAYLIST)" -ForegroundColor Cyan
}
else {
    Write-Host " STEP 1 - QUERY AUDIO (SINGLE VIDEO)" -ForegroundColor Cyan
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 调用查询脚本
$QueryResult = & $QueryScript `
    -Url $Url `
    -PlaylistTitle $PlaylistTitle `
-Mode $Mode
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: query script failed." -ForegroundColor Red
    exit 1
}

$QueryInfo = $QueryResult |
    Where-Object {
        $_.PSObject.Properties.Name -contains "SelectionFile"
    } |
    Select-Object -Last 1

if ($null -eq $QueryInfo) {

    Write-Host ""
    Write-Host "ERROR: Query result not found." -ForegroundColor Red

    exit 1
}

$SelectionFile = [string]$QueryInfo.SelectionFile
$DownloadDir   = [string]$QueryInfo.DownloadDir
$RawJson       = [string]$QueryInfo.RawJson

if (-not (Test-Path -LiteralPath $SelectionFile)) {

    Write-Host ""
    Write-Host "ERROR: Selection file not found:" -ForegroundColor Red
    Write-Host $SelectionFile

    exit 1
}


# ============================================================
# 读取 Audio Selection
# ============================================================

$AudioIds = @()

$Lines = Get-Content `
    -LiteralPath $SelectionFile `
    -Encoding UTF8

foreach ($Line in $Lines) {

    if ([string]::IsNullOrWhiteSpace($Line)) {
        continue
    }

    $Parts = $Line -split "\|"

    if ($Parts.Count -ge 3) {

        $Source   = $Parts[0]
        $Language = $Parts[1]
        $FormatId = $Parts[2]

        if (-not [string]::IsNullOrWhiteSpace($FormatId)) {

            $AudioIds += $FormatId

            Write-Host "Audio: $Language -> $FormatId ($Source)"
        }
    }
}

$AudioIds = @(
    $AudioIds |
    Select-Object -Unique
)


# ============================================================
# Audio fallback
# ============================================================

if ($AudioIds.Count -eq 0) {

    Write-Host ""
    Write-Host "WARNING: No Opus audio selected. Generic audio fallback will be used." -ForegroundColor Yellow

    $AudioPart = "ba*"
}
else {

    $AudioPart = ($AudioIds -join "+")
}


# ============================================================
# STEP 2
# FORMAT SELECTOR
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " STEP 2 - FORMAT SELECTION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($Mode -eq "Phonics") {

    # 1. AV1 独立视频
    $AV1_720 = "bv*[vcodec^=av01][height<=720][height>480][fps<=30][dynamic_range!*=HDR]"
    $AV1_480 = "bv*[vcodec^=av01][height<=480][height>=360][fps<=30][dynamic_range!*=HDR]"

    # 2. 已合并 AV1
    $AV1_Merged_720 = "b[vcodec^=av01][height<=720][height>480][fps<=30][dynamic_range!*=HDR]"
    $AV1_Merged_480 = "b[vcodec^=av01][height<=480][height>=360][fps<=30][dynamic_range!*=HDR]"

    # 3. VP9 独立视频
    $VP9_720 = "bv*[vcodec^=vp9][height<=720][height>480][fps<=30][dynamic_range!*=HDR]"
    $VP9_480 = "bv*[vcodec^=vp9][height<=480][height>=360][fps<=30][dynamic_range!*=HDR]"

    # 4. 已合并 VP9
    $VP9_Merged_720 = "b[vcodec^=vp9][height<=720][height>480][fps<=30][dynamic_range!*=HDR]"
    $VP9_Merged_480 = "b[vcodec^=vp9][height<=480][height>=360][fps<=30][dynamic_range!*=HDR]"

    # 5. AVC1 独立视频
    $AVC1_480 = "bv*[vcodec^=avc1][height<=480][height>=360][fps<=30][dynamic_range!*=HDR]"

    # 6. 已合并 AVC1
    $AVC1_Merged_480 = "b[vcodec^=avc1][height<=480][height>=360][fps<=30][dynamic_range!*=HDR]"


    $FormatSelector =
        "$AV1_720+$AudioPart/" +
        "$VP9_720+$AudioPart/" +
        "$AV1_480+$AudioPart/" +
        "$VP9_480+$AudioPart/" +
        "$AV1_Merged_720+$AudioPart/" +
        "$VP9_Merged_720+$AudioPart/" +
        "$AV1_Merged_480+$AudioPart/" +
        "$VP9_Merged_480+$AudioPart/" +
        "$AVC1_480+$AudioPart/" +      
        "$AVC1_Merged_480+$AudioPart/" +
	    "b[height<=720]+$AudioPart"
}



else {

    # ========================================
    # Movie：若未传入参数则询问；Playlist 子进程会带参数进来
    # ========================================

    if ($MaxHeight -le 0) {

        Write-Host ""
        Write-Host "=== MOVIE FORMAT PREFERENCE ===" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Max resolution:"
        Write-Host "  1 = 2160 (4K)"
        Write-Host "  2 = 1440 (2K)"
        Write-Host "  3 = 1080 (默认)"
        Write-Host "  4 = 720"
        Write-Host ""

        $ResChoice = Read-Host "Select [1-4] (default 3)"
        if ([string]::IsNullOrWhiteSpace($ResChoice)) { $ResChoice = "3" }

        switch ($ResChoice) {
            "1" { $MaxHeight = 2160 }
            "2" { $MaxHeight = 1440 }
            "4" { $MaxHeight = 720 }
            default { $MaxHeight = 1080 }
        }
    }

    if ([string]::IsNullOrWhiteSpace($PreferCodec)) {

        Write-Host ""
        Write-Host "Preferred video codec:"
        Write-Host "  1 = AV1 优先 (默认)"
        Write-Host "  2 = VP9 优先"
        Write-Host "  3 = AVC1 优先"
        Write-Host ""

        $CodecChoice = Read-Host "Select [1-3] (default 1)"
        if ([string]::IsNullOrWhiteSpace($CodecChoice)) { $CodecChoice = "1" }

        switch ($CodecChoice) {
            "2" { $PreferCodec = "vp9" }
            "3" { $PreferCodec = "avc1" }
            default { $PreferCodec = "av01" }
        }
    }

    switch ($MaxHeight) {
        2160 { $MinHeight = 1440 }
        1440 { $MinHeight = 1080 }
        720  { $MinHeight = 480 }
        default {
            $MaxHeight = 1080
            $MinHeight = 720
        }
    }

    # 编码优先级（与你的要求一致）
    switch ($PreferCodec) {
        "vp9" {
            $MainCodecs = @("vp9", "av01")   # 主循环：VP9 → AV1
            $PreferCodec = "vp9"
        }
        "avc1" {
            $MainCodecs = @("avc1", "av01", "vp9")  # AVC1 优先时，主循环含全部
            $PreferCodec = "avc1"
        }
        default {
            $MainCodecs = @("av01", "vp9")   # 默认：AV1 → VP9
            $PreferCodec = "av01"
        }
    }

    Write-Host ""
    Write-Host "Selected : max ${MaxHeight}p | main: $($MainCodecs -join ' > ') | then avc1 fallback tiers" -ForegroundColor Yellow
    Write-Host ""

    # ------------------------------------------------
    # 选择顺序（对齐 Phonics）：
    # 1) 主编码 独立 最高
    # 2) 主编码 独立 次高
    # 3) 主编码 已合并 最高
    # 4) 主编码 已合并 次高
    # 5) AVC1 独立 最高 / 次高（若主循环里还没有 avc1）
    # 6) AVC1 已合并 最高 / 次高
    # 7) 兜底
    # ------------------------------------------------

    $Parts = @()

    # 1. 主编码：独立 + 最高档
    foreach ($Codec in $MainCodecs) {
        $Parts += "bv*[vcodec^=$Codec][height<=$MaxHeight][height>$MinHeight][fps<=60]+$AudioPart"
    }

    # 2. 主编码：独立 + 次高档
    foreach ($Codec in $MainCodecs) {
        $Parts += "bv*[vcodec^=$Codec][height<=$MinHeight][height>=480][fps<=60]+$AudioPart"
    }

    # 3. 主编码：已合并 + 最高档
    foreach ($Codec in $MainCodecs) {
        $Parts += "b[vcodec^=$Codec][height<=$MaxHeight][height>$MinHeight][fps<=60]+$AudioPart"
    }

    # 4. 主编码：已合并 + 次高档
    foreach ($Codec in $MainCodecs) {
        $Parts += "b[vcodec^=$Codec][height<=$MinHeight][height>=480][fps<=60]+$AudioPart"
    }

    # 5–6. 若主循环里没有 avc1，则把 AVC1 放到最后（与 Phonics 一致）
    if ($MainCodecs -notcontains "avc1") {
        $Parts += "bv*[vcodec^=avc1][height<=$MaxHeight][height>$MinHeight][fps<=60]+$AudioPart"
        $Parts += "bv*[vcodec^=avc1][height<=$MinHeight][height>=480][fps<=60]+$AudioPart"
        $Parts += "b[vcodec^=avc1][height<=$MaxHeight][height>$MinHeight][fps<=60]+$AudioPart"
        $Parts += "b[vcodec^=avc1][height<=$MinHeight][height>=480][fps<=60]+$AudioPart"
    }

    # 7. 最终兜底
    $Parts += "b+$AudioPart"

    $FormatSelector = $Parts -join "/"
}




Write-Host "Audio streams : $($AudioIds.Count)"
Write-Host "Audio formats : $AudioPart"

Write-Host ""
Write-Host "Format selector:"
Write-Host $FormatSelector -ForegroundColor Yellow






# ============================================================
# 检查是否已有完整 MKV（跳过已完成）
# ============================================================

$ExistingMkv = $null

if ($PlaylistIndex -gt 0) {
    # Playlist：只认带当前序号前缀的文件，例如 "003 - xxx.mkv"
    $IndexPrefixForSkip = "{0:D3} - " -f $PlaylistIndex

    $ExistingMkv = Get-ChildItem `
        -LiteralPath $DownloadDir `
        -Filter "*.mkv" `
        -File `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.StartsWith($IndexPrefixForSkip) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}
else {
    # 单视频：目录是按标题分的，有 mkv 即视为已完成
    $ExistingMkv = Get-ChildItem `
        -LiteralPath $DownloadDir `
        -Filter "*.mkv" `
        -File `
        -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if ($null -ne $ExistingMkv) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " SKIP - ALREADY COMPLETE" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Existing MKV : $($ExistingMkv.Name)"
    Write-Host "Size         : $([math]::Round($ExistingMkv.Length / 1MB, 2)) MiB"
    Write-Host "Skip download and post-processing."
    Write-Host ""
    exit 0
}





# ============================================================
# STEP 3
# 正式下载
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " STEP 3 - DOWNLOAD" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($PlaylistIndex -gt 0) {
    $IndexPrefix = "{0:D3} - " -f $PlaylistIndex
}
else {
    $IndexPrefix = ""
}

$OutputTemplate = Join-Path `
    $DownloadDir `
    "$IndexPrefix%(title)s - %(upload_date>%Y-%m-%d)s.%(ext)s"

$SubtitleTemplate = Join-Path `
    $DownloadDir `
    "$IndexPrefix%(title)s - %(upload_date>%Y-%m-%d)s.%(language)s.%(ext)s"
    
$YtArgs = @( 
    "--config-location", $Config 
    "--cookies", $Cookies 
    "-f", $FormatSelector 
    "-o", $OutputTemplate
    "-o", "subtitle:$SubtitleTemplate"
    $Url 
)

# 保存 yt-dlp 输出，最后再显示选中的 Video Format ID
& $YtDlp @YtArgs
$DownloadExitCode = $LASTEXITCODE

if ($DownloadExitCode -ne 0) {

    Write-Host ""
    Write-Host "ERROR: yt-dlp download failed." -ForegroundColor Red

    exit $DownloadExitCode
}


# ============================================================
# STEP 4
# 找最新 MKV
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " STEP 4 - FIND MKV" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$Mkv = Get-ChildItem `
    -LiteralPath $DownloadDir `
    -Filter "*.mkv" `
    -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $Mkv) {

    Write-Host ""
    Write-Host "ERROR: MKV file not found." -ForegroundColor Red

    exit 1
}

$MkvPath = $Mkv.FullName

Write-Host "MKV:"
Write-Host $MkvPath


# ============================================================
# STEP 5
# English auto-generated
# ============================================================

Add-EnglishAutoSubtitle `
    -Mkv $MkvPath `
    -Json $RawJson


# ============================================================
# STEP 6
# Subtitle title
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " STEP 6 - SUBTITLE TITLES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Set-SubtitleTitles `
    -Mkv $MkvPath `
    -Json $RawJson


# ============================================================
# CLEANUP
# 所有处理完成以后才删除临时文件
# ============================================================

Remove-TemporaryFiles `
    -Mkv $MkvPath


# ============================================================
# STEP 7
# FINAL SUMMARY
# ============================================================

Show-FinalSummary `
    -Mkv $MkvPath `
    -Json $RawJson `
    -SelectionFile $SelectionFile `
    -SelectedVideoFormat $SelectedVideoFormat


# ============================================================
# COMPLETE
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " DOWNLOAD COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "File:"
Write-Host $MkvPath

Write-Host ""
