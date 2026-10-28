# download-other.ps1 — generic sites, feature-aligned with YouTube script
# Expected path: D:\yt-dlp\other\download-other.ps1
#
# Usage:
#   cd D:\yt-dlp\other
#   .\download-other.ps1 "https://..."
#   .\download-other.ps1 "URL" -Mode Phonics
#   .\download-other.ps1 "URL" -MaxHeight 1080 -PreferCodec av01
#   .\download-other.ps1 "PLAYLIST_URL" -PlaylistIndexRange "1-5"

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

$Root         = "D:\yt-dlp"
$YtDlp        = Join-Path $Root "yt-dlp.exe"
$FFmpeg       = Join-Path $Root "ffmpeg.exe"
$FFprobe      = Join-Path $Root "ffprobe.exe"
$Config      = Join-Path $PSScriptRoot "config_generic"
$QueryScript = Join-Path $PSScriptRoot "query-generic.ps1"
$Cookies      = Join-Path $Root "cookies.txt"

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -le 0) { return "-" }
    if ($Bytes -ge 1GB) { return "{0:N2} GiB" -f ($Bytes / 1GB) }
    return "{0:N2} MiB" -f ($Bytes / 1MB)
}

function Invoke-FFmpegSafe {
    param([Parameter(ValueFromRemainingArguments = $true)]$FFmpegArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $FFmpeg -hide_banner -loglevel error @FFmpegArgs 2>&1 | Out-Null
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prev
    }
}

function Remove-TemporaryFiles {
    param([string]$Mkv)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " CLEANUP" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $dir = [System.IO.Path]::GetDirectoryName($Mkv)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Mkv)
    $mkvName = [System.IO.Path]::GetFileName($Mkv)

    $candidates = Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ne $mkvName -and (
                $_.BaseName -eq $name -or $_.Name.StartsWith($name + ".")
            )
        }
    foreach ($f in $candidates) {
        $ext = $f.Extension.ToLowerInvariant()
        if ($ext -in @(".webp", ".jpg", ".png", ".vtt", ".srt") -or $f.Name.EndsWith(".description")) {
            Write-Host "[Cleanup] $($f.Name)"
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Set-SubtitleTitles {
    param([string]$Mkv, [string]$Json)
    if (-not (Test-Path -LiteralPath $Json)) {
        Write-Host "Subtitle titles  : info.json not found" -ForegroundColor Yellow
        return
    }
    try {
        $j = Get-Content -LiteralPath $Json -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Host "Subtitle titles  : Failed to read info.json" -ForegroundColor Red
        return
    }

    $names = @()
    if ($null -ne $j.subtitles) {
        $names = @(
            $j.subtitles.PSObject.Properties |
            ForEach-Object { ($_.Value | Select-Object -First 1).name }
        )
    }

    $count = @(& $FFprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 $Mkv 2>$null).Count
    if ($count -eq 0) {
        Write-Host "Subtitle streams : 0"
        Write-Host "Subtitle titles  : None"
        return
    }

    $tmp = [System.IO.Path]::ChangeExtension($Mkv, ".title.mkv")
    $args = @("-y", "-i", $Mkv, "-map", "0", "-c", "copy")
    $UpdatedCount = 0
    for ($i = 0; $i -lt $count; $i++) {
        if ($i -lt $names.Count -and $names[$i]) {
            $args += "-metadata:s:s:$i"
            $args += "title=$([string]$names[$i])"
            $UpdatedCount++
        }
    }
    $ec = Invoke-FFmpegSafe @args $tmp
    if ($ec -ne 0) {
        Write-Host "Subtitle titles  : Failed" -ForegroundColor Red
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return
    }
    Move-Item -LiteralPath $tmp -Destination $Mkv -Force
    Write-Host "Subtitle streams : $count"
    Write-Host "Subtitle titles  : Updated ($UpdatedCount)"
}

function Add-EnglishAutoSubtitle {
    param([string]$Mkv, [string]$Json)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " STEP 5 - ENGLISH AUTO SUBTITLE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $Json)) {
        Write-Host "English auto subtitle : info.json not found" -ForegroundColor Yellow
        return
    }
    try {
        $Info = Get-Content -LiteralPath $Json -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Host "English auto subtitle : Failed to read info.json" -ForegroundColor Red
        return
    }

    $AutoCaption = $null
    if ($null -ne $Info.automatic_captions) {
        $AutoCaption = $Info.automatic_captions.'en-orig'
    }
    if ($null -eq $AutoCaption) {
        Write-Host "English auto subtitle : Not found (normal for many sites)" -ForegroundColor Yellow
        return
    }

    $SubtitleEntry = @($AutoCaption | Where-Object { $_.url -and $_.ext -eq "vtt" } | Select-Object -First 1)
    if ($null -eq $SubtitleEntry) {
        Write-Host "English auto subtitle : No usable VTT" -ForegroundColor Yellow
        return
    }

    $base = [System.IO.Path]::ChangeExtension($Mkv, $null).TrimEnd('.')
    $vtt = "$base.en-orig.vtt"
    $tmp = "$base.auto-vtt.mkv"

    try {
        Invoke-WebRequest -Uri ([string]$SubtitleEntry.url) -OutFile $vtt -UseBasicParsing *> $null
    }
    catch {
        Write-Host "Subtitle download     : Failed" -ForegroundColor Red
        return
    }
    if (-not (Test-Path -LiteralPath $vtt)) {
        Write-Host "Subtitle download     : Failed" -ForegroundColor Red
        return
    }
    Write-Host "Subtitle download     : OK" -ForegroundColor Green

    $SubtitleCount = @(& $FFprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 $Mkv 2>$null).Count
    $ec = Invoke-FFmpegSafe -y -i $Mkv -i $vtt -map 0 -map 1:0 -c copy `
        "-metadata:s:s:$SubtitleCount" "language=eng" `
        "-metadata:s:s:$SubtitleCount" "title=English (auto-generated)" `
        $tmp
    if ($ec -ne 0 -or -not (Test-Path -LiteralPath $tmp)) {
        Write-Host "Subtitle embedding    : Failed" -ForegroundColor Red
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return
    }
    Move-Item -LiteralPath $tmp -Destination $Mkv -Force
    Write-Host "Subtitle embedding    : OK" -ForegroundColor Green
}

# ============================================================
# PLAYLIST MODE (generic: if yt-dlp returns entries)
# ============================================================

$TryPlaylist = $false
if ([string]::IsNullOrWhiteSpace($PlaylistTitle)) {
    # Heuristic: common list URL patterns + allow any URL if user wants range
    if ($Url -match '(?i)(list=|/playlist|/series|/collections?/|/channel/|/videos)') {
        $TryPlaylist = $true
    }
}

if ($TryPlaylist) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " PLAYLIST MODE (other)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $PlaylistArgs = @(
        "--no-warnings"
        "--flat-playlist"
        "--dump-single-json"
        "--ignore-no-formats-error"
        "--cookies", $Cookies
        "--remote-components", "ejs:github"
        $Url
    )
    if ($Url -match '(?i)(youtube\.com|youtu\.be)') {
        $PlaylistArgs = @(
            "--no-warnings", "--flat-playlist", "--dump-single-json", "--ignore-no-formats-error",
            "--cookies", $Cookies, "--remote-components", "ejs:github",
            "--extractor-args", "youtube:player_client=default,web_embedded;skip=translated_subs",
            $Url
        )
    }

    Write-Host "[1/3] Reading playlist..."
    $PlaylistJsonText = & $YtDlp @PlaylistArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Playlist query failed; fallback to single URL." -ForegroundColor Yellow
        $TryPlaylist = $false
    }
    else {
        if ($PlaylistJsonText -is [System.Array]) {
            $PlaylistJsonText = ($PlaylistJsonText | ForEach-Object { "$_" }) -join "`n"
        }
        $Start = ([string]$PlaylistJsonText).IndexOf("{")
        if ($Start -lt 0) {
            Write-Host "WARNING: No playlist JSON; fallback to single URL." -ForegroundColor Yellow
            $TryPlaylist = $false
        }
        else {
            $PlaylistJsonText = ([string]$PlaylistJsonText).Substring($Start)
            try {
                $PlaylistInfo = $PlaylistJsonText | ConvertFrom-Json
            }
            catch {
                Write-Host "WARNING: Playlist parse failed; fallback to single URL." -ForegroundColor Yellow
                $TryPlaylist = $false
            }
        }
    }
}

if ($TryPlaylist -and $null -ne $PlaylistInfo) {
    $PlaylistTitle = [string]$PlaylistInfo.title
    if ([string]::IsNullOrWhiteSpace($PlaylistTitle)) { $PlaylistTitle = "Playlist" }

    $Entries = @($PlaylistInfo.entries | Where-Object { $_ -and ($_.id -or $_.url -or $_.webpage_url) })
    if ($Entries.Count -eq 0) {
        Write-Host "WARNING: No entries; fallback to single URL." -ForegroundColor Yellow
        $TryPlaylist = $false
        $PlaylistTitle = ""
    }
    else {
        Write-Host "Playlist : $PlaylistTitle"
        Write-Host "Videos   : $($Entries.Count)"

        $SelectedIndexes = $null
        if (-not [string]::IsNullOrWhiteSpace($PlaylistIndexRange)) {
            $SelectedIndexes = [System.Collections.Generic.HashSet[int]]::new()
            foreach ($Part in ($PlaylistIndexRange -split ",")) {
                $Part = $Part.Trim()
                if ($Part -match '^\s*(\d+)\s*-\s*(\d+)\s*$') {
                    $a = [int]$Matches[1]; $b = [int]$Matches[2]
                    if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
                    for ($i = $a; $i -le $b; $i++) { [void]$SelectedIndexes.Add($i) }
                }
                elseif ($Part -match '^\s*(\d+)\s*$') {
                    [void]$SelectedIndexes.Add([int]$Part)
                }
                else {
                    Write-Host "ERROR: Invalid PlaylistIndexRange: $Part" -ForegroundColor Red
                    exit 1
                }
            }
            Write-Host "Selected indexes: $((($SelectedIndexes | Sort-Object) -join ', '))" -ForegroundColor Cyan
        }

        if ($Mode -eq "Movie" -and $MaxHeight -le 0) {
            Write-Host ""
            Write-Host "=== MOVIE FORMAT (Playlist, ask once) ===" -ForegroundColor Cyan
            Write-Host "Max resolution: 1=2160 2=1440 3=1080(default) 4=720"
            $ResChoice = Read-Host "Select [1-4] (default 3)"
            if ([string]::IsNullOrWhiteSpace($ResChoice)) { $ResChoice = "3" }
            switch ($ResChoice) {
                "1" { $MaxHeight = 2160 }
                "2" { $MaxHeight = 1440 }
                "4" { $MaxHeight = 720 }
                default { $MaxHeight = 1080 }
            }
            if ([string]::IsNullOrWhiteSpace($PreferCodec)) {
                Write-Host "Codec: 1=av01 2=vp9 3=avc1 (default 1)"
                $CodecChoice = Read-Host "Select [1-3] (default 1)"
                if ([string]::IsNullOrWhiteSpace($CodecChoice)) { $CodecChoice = "1" }
                switch ($CodecChoice) {
                    "2" { $PreferCodec = "vp9" }
                    "3" { $PreferCodec = "avc1" }
                    default { $PreferCodec = "av01" }
                }
            }
            Write-Host "Playlist will use: max ${MaxHeight}p | $PreferCodec" -ForegroundColor Yellow
        }

        $SuccessCount = 0; $FailCount = 0; $Results = @()
        $Index = 0
        foreach ($Entry in $Entries) {
            $Index++
            if ($null -ne $SelectedIndexes -and -not $SelectedIndexes.Contains($Index)) { continue }

            if ($Entry.webpage_url) { $VideoUrl = [string]$Entry.webpage_url }
            elseif ($Entry.url -match '^https?://') { $VideoUrl = [string]$Entry.url }
            elseif ($Entry.id -and $Url -match '(?i)youtube') {
                $VideoUrl = "https://www.youtube.com/watch?v=$($Entry.id)"
            }
            elseif ($Entry.url) { $VideoUrl = [string]$Entry.url }
            else { continue }

            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host " ITEM $Index / $($Entries.Count)" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "URL: $VideoUrl"

            & $PSCommandPath $VideoUrl `
                -PlaylistTitle $PlaylistTitle `
                -Mode $Mode `
                -PlaylistIndex $Index `
                -MaxHeight $MaxHeight `
                -PreferCodec $PreferCodec

            $code = $LASTEXITCODE
            $title = if ($Entry.title) { [string]$Entry.title } else { [string]$Entry.id }
            if ($code -eq 0) { $SuccessCount++; $st = "OK" }
            else { $FailCount++; $st = "FAILED"; Write-Host "WARNING: item failed, continue..." -ForegroundColor Yellow }

            $Results += [PSCustomObject]@{ Index = $Index; Id = [string]$Entry.id; Title = $title; Status = $st }
        }

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host " PLAYLIST COMPLETE" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Succeeded : $SuccessCount" -ForegroundColor Green
        Write-Host "Failed    : $FailCount" -ForegroundColor $(if ($FailCount -gt 0) { "Red" } else { "Green" })
        if ($Results.Count -gt 0) {
            $Results | Format-Table -AutoSize Index, Status, Id, Title | Out-Host
        }
        exit 0
    }
}

# ============================================================
# SINGLE VIDEO
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " STEP 1 - QUERY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$QueryResult = & $QueryScript -Url $Url -PlaylistTitle $PlaylistTitle -Mode $Mode
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: query failed." -ForegroundColor Red
    exit 1
}

$QueryInfo = $QueryResult |
    Where-Object { $_.PSObject.Properties.Name -contains "SelectionFile" } |
    Select-Object -Last 1
if ($null -eq $QueryInfo) {
    Write-Host "ERROR: Query result not found." -ForegroundColor Red
    exit 1
}

$SelectionFile = [string]$QueryInfo.SelectionFile
$DownloadDir   = [string]$QueryInfo.DownloadDir
$RawJson       = [string]$QueryInfo.RawJson

if (-not (Test-Path -LiteralPath $SelectionFile)) {
    Write-Host "ERROR: Selection file not found." -ForegroundColor Red
    exit 1
}

$AudioIds = @()
Get-Content -LiteralPath $SelectionFile -Encoding UTF8 | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    $p = $_ -split "\|"
    if ($p.Count -ge 3 -and $p[2]) {
        $AudioIds += $p[2]
        Write-Host "Audio: $($p[1]) -> $($p[2]) ($($p[0]))"
    }
}
$AudioIds = @($AudioIds | Select-Object -Unique)
$AudioPart = if ($AudioIds.Count -eq 0) { "ba*" } else { ($AudioIds -join "+") }

# STEP 2 FORMAT
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " STEP 2 - FORMAT SELECTION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($Mode -eq "Phonics") {
    if ($MaxHeight -le 0) { $MaxHeight = 720 }
    $FormatSelector = (
        "bv*[height<=720][height>480][fps<=30]+$AudioPart/" +
        "bv*[height<=480][height>=360][fps<=30]+$AudioPart/" +
        "b[height<=720]+$AudioPart/" +
        "b+$AudioPart"
    )
}
else {
    if ($MaxHeight -le 0) {
        Write-Host "Max resolution: 1=2160 2=1440 3=1080(default) 4=720"
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
        Write-Host "Codec preference: 1=av01 2=vp9 3=avc1 (default 1) — used when available"
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
        default { $MaxHeight = 1080; $MinHeight = 720 }
    }

    switch ($PreferCodec) {
        "vp9"  { $MainCodecs = @("vp9", "av01") }
        "avc1" { $MainCodecs = @("avc1", "av01", "vp9") }
        default { $MainCodecs = @("av01", "vp9"); $PreferCodec = "av01" }
    }

    $Parts = @()
    foreach ($c in $MainCodecs) {
        $Parts += "bv*[vcodec^=$c][height<=$MaxHeight][height>$MinHeight]+$AudioPart"
    }
    foreach ($c in $MainCodecs) {
        $Parts += "bv*[vcodec^=$c][height<=$MinHeight][height>=480]+$AudioPart"
    }
    foreach ($c in $MainCodecs) {
        $Parts += "b[vcodec^=$c][height<=$MaxHeight][height>$MinHeight]+$AudioPart"
    }
    foreach ($c in $MainCodecs) {
        $Parts += "b[vcodec^=$c][height<=$MinHeight][height>=480]+$AudioPart"
    }
    if ($MainCodecs -notcontains "avc1") {
        $Parts += "bv*[vcodec^=avc1][height<=$MaxHeight]+$AudioPart"
        $Parts += "b[vcodec^=avc1][height<=$MaxHeight]+$AudioPart"
    }
    $Parts += "bv*[height<=$MaxHeight]+$AudioPart"
    $Parts += "b[height<=$MaxHeight]+$AudioPart"
    $Parts += "b+$AudioPart"
    $FormatSelector = $Parts -join "/"
}

Write-Host "Max height : $MaxHeight | prefer $PreferCodec"
Write-Host "Audio      : $AudioPart"
Write-Host "Selector   :"
Write-Host $FormatSelector -ForegroundColor Yellow

# Skip existing
$ExistingMkv = $null
if ($PlaylistIndex -gt 0) {
    $prefix = "{0:D3} - " -f $PlaylistIndex
    $ExistingMkv = Get-ChildItem -LiteralPath $DownloadDir -Filter "*.mkv" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.StartsWith($prefix) } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
else {
    $ExistingMkv = Get-ChildItem -LiteralPath $DownloadDir -Filter "*.mkv" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if ($null -ne $ExistingMkv) {
    Write-Host ""
    Write-Host "SKIP - ALREADY COMPLETE: $($ExistingMkv.Name)" -ForegroundColor Green
    exit 0
}

# STEP 3 DOWNLOAD
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " STEP 3 - DOWNLOAD" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
$IndexPrefix = if ($PlaylistIndex -gt 0) { "{0:D3} - " -f $PlaylistIndex } else { "" }
$OutputTemplate   = Join-Path $DownloadDir "$IndexPrefix%(title)s - %(upload_date>%Y-%m-%d|unknown)s.%(ext)s"
$SubtitleTemplate = Join-Path $DownloadDir "$IndexPrefix%(title)s - %(upload_date>%Y-%m-%d|unknown)s.%(language)s.%(ext)s"

$YtArgs = @(
    "--config-location", $Config
    "--cookies", $Cookies
    "-f", $FormatSelector
    "-o", $OutputTemplate
    "-o", "subtitle:$SubtitleTemplate"
    $Url
)
& $YtDlp @YtArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: download failed." -ForegroundColor Red
    exit $LASTEXITCODE
}

# STEP 4 FIND MKV
$Mkv = Get-ChildItem -LiteralPath $DownloadDir -Filter "*.mkv" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $Mkv) {
    Write-Host "ERROR: MKV not found." -ForegroundColor Red
    exit 1
}
$MkvPath = $Mkv.FullName
Write-Host "MKV: $MkvPath"

Add-EnglishAutoSubtitle -Mkv $MkvPath -Json $RawJson

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " STEP 6 - SUBTITLE TITLES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Set-SubtitleTitles -Mkv $MkvPath -Json $RawJson

Remove-TemporaryFiles -Mkv $MkvPath

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " DOWNLOAD COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "File: $MkvPath"
Write-Host ""
