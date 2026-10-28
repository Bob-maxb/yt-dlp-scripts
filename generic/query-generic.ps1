# query-other.ps1 — generic sites (also works for YouTube)
# Expected path: D:\yt-dlp\other\query-other.ps1

param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$PlaylistTitle = "",

    [ValidateSet("Movie", "Phonics")]
    [string]$Mode = "Movie",

    [switch]$Adult
)

$ErrorActionPreference = "Stop"

$Root  = "D:\yt-dlp"
$YtDlp = Join-Path $Root "yt-dlp.exe"

if ($Mode -eq "Phonics") {
    $BaseDir = "D:\10 Learning\English\Phonics"
}
elseif ($Adult) {
    $BaseDir = "D:\03 Media\Adult"
}
else {
    $BaseDir = "D:\03 Media\Movies & TV"
}

function Get-SafeFolderName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "Single Files" }
    $Safe = $Name -replace '[<>:"/\\|?*]', '_'
    $Safe = $Safe.TrimEnd(' ', '.')
    if ([string]::IsNullOrWhiteSpace($Safe)) { return "Single Files" }
    return $Safe
}

Write-Host ""
Write-Host "=== QUERY VIDEO (other) ===" -ForegroundColor Cyan
Write-Host $Url
Write-Host ""

$IsYouTube = $Url -match '(?i)(youtube\.com|youtu\.be)'

$YtArgs = @(
    "--no-warnings"
    "--skip-download"
    "--dump-single-json"
    "--ignore-no-formats-error"
    "--cookies", (Join-Path $Root "cookies.txt")
    "--remote-components", "ejs:github"
)
if ($IsYouTube) {
    $YtArgs += @("--extractor-args", "youtube:player_client=default,web_embedded;skip=translated_subs")
}
$YtArgs += $Url

$JsonText = & $YtDlp @YtArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: yt-dlp query failed." -ForegroundColor Red
    $JsonText
    exit 1
}

if ($JsonText -is [System.Array]) {
    $JsonText = ($JsonText | ForEach-Object { "$_" }) -join "`n"
}
else {
    $JsonText = [string]$JsonText
}

$Start = $JsonText.IndexOf("{")
if ($Start -lt 0) {
    Write-Host "ERROR: JSON not found." -ForegroundColor Red
    exit 1
}
$JsonText = $JsonText.Substring($Start)

try { $Info = $JsonText | ConvertFrom-Json }
catch {
    Write-Host "ERROR: JSON parse failed." -ForegroundColor Red
    exit 1
}

$VideoId = [string]$Info.id
if ([string]::IsNullOrWhiteSpace($VideoId)) { $VideoId = "unknown" }

$UploadDate = [string]$Info.upload_date
if ($UploadDate -match '^(\d{4})(\d{2})(\d{2})$') {
    $DateFolder = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
}
else {
    $UploadDate = (Get-Date).ToString("yyyyMMdd")
    $DateFolder = (Get-Date).ToString("yyyy-MM-dd")
    Write-Host "WARNING: upload_date missing; using $DateFolder" -ForegroundColor Yellow
}

$VideoTitle = Get-SafeFolderName $Info.title

if ([string]::IsNullOrWhiteSpace($PlaylistTitle)) {
    $DownloadDir = Join-Path (Join-Path $BaseDir "Single Files") $VideoTitle
    $IsPlaylist = $false
}
else {
    $PlaylistFolder = Get-SafeFolderName $PlaylistTitle
    if ($Mode -eq "Phonics") {
        $DownloadDir = Join-Path $BaseDir $PlaylistFolder
    }
    else {
        $DownloadDir = Join-Path (Join-Path $BaseDir "Playlist") $PlaylistFolder
    }
    $IsPlaylist = $true
}

$JsonDir = Join-Path $DownloadDir "json"
New-Item -ItemType Directory -Force -Path $JsonDir | Out-Null

$FileBaseName   = "$VideoTitle - $UploadDate"
$RawJson        = Join-Path $JsonDir "$FileBaseName.info.json"
$SelectionFile  = Join-Path $JsonDir "$FileBaseName.audio-selection.txt"
$JsonText | Set-Content -LiteralPath $RawJson -Encoding UTF8

# Audio: Opus -> AAC -> any pure audio
$AudioFormats = @()
if ($null -ne $Info.formats) {
    $AudioFormats = @($Info.formats | Where-Object { $_.acodec -like "opus*" -and $_.vcodec -eq "none" })
    if ($AudioFormats.Count -eq 0) {
        $AudioFormats = @($Info.formats | Where-Object {
            $_.vcodec -eq "none" -and $_.acodec -and $_.acodec -ne "none" -and (
                $_.acodec -like "mp4a*" -or $_.acodec -like "aac*"
            )
        })
        if ($AudioFormats.Count -gt 0) {
            Write-Host "WARNING: No Opus; using AAC." -ForegroundColor Yellow
        }
    }
    if ($AudioFormats.Count -eq 0) {
        $AudioFormats = @($Info.formats | Where-Object {
            $_.vcodec -eq "none" -and $_.acodec -and $_.acodec -ne "none"
        })
        if ($AudioFormats.Count -gt 0) {
            Write-Host "WARNING: Using generic pure audio." -ForegroundColor Yellow
        }
    }
}

Write-Host "Video ID       : $VideoId"
Write-Host "Playlist       : $PlaylistTitle"
Write-Host "Download dir   : $DownloadDir"
Write-Host "Audio formats  : $($AudioFormats.Count)"
Write-Host "Site           : $(if ($IsYouTube) { 'YouTube' } else { 'Other' })"

# VIDEO FORMAT SUMMARY
Write-Host ""
Write-Host "=== VIDEO FORMAT SUMMARY ===" -ForegroundColor Cyan
$VideoFormats = @()
if ($null -ne $Info.formats) {
    $VideoFormats = @(
        $Info.formats |
        Where-Object { $_.vcodec -and $_.vcodec -ne "none" } |
        Sort-Object `
            @{ Expression = { if ($_.height) { [int]$_.height } else { 0 } }; Descending = $true },
            @{ Expression = { if ($_.fps) { [double]$_.fps } else { 0 } }; Descending = $true }
    )
}
if ($VideoFormats.Count -eq 0) {
    Write-Host "None"
}
else {
    $VideoFormats | ForEach-Object {
        $Resolution = if ($_.width -and $_.height) { "$($_.width)x$($_.height)" } else { "-" }
        $FPS = if ($_.fps) { "$($_.fps)" } else { "-" }
        $Type = if ($_.acodec -and $_.acodec -ne "none") { "video+audio" } else { "video-only" }
        $Vbr = if ($_.vbr) { "{0:N0}k" -f [double]$_.vbr } elseif ($_.tbr) { "~{0:N0}k" -f [double]$_.tbr } else { "-" }
        $Size = "-"
        if ($_.filesize) {
            $b = [double]$_.filesize
            $Size = if ($b -ge 1GB) { "{0:N2} GiB" -f ($b / 1GB) } else { "{0:N1} MiB" -f ($b / 1MB) }
        }
        elseif ($_.filesize_approx) {
            $b = [double]$_.filesize_approx
            $Size = if ($b -ge 1GB) { "~{0:N2} GiB" -f ($b / 1GB) } else { "~{0:N1} MiB" -f ($b / 1MB) }
        }
        $Hdr = if ($_.dynamic_range) { [string]$_.dynamic_range }
               elseif ("$($_.format_note)$($_.vcodec)" -match '(?i)hdr') { "HDR" } else { "SDR" }
        [PSCustomObject]@{
            ID = $_.format_id; CODEC = $_.vcodec; RESOLUTION = $Resolution
            FPS = $FPS; VBR = $Vbr; SIZE = $Size; HDR = $Hdr; TYPE = $Type
        }
    } | Format-Table -AutoSize | Out-Host
}

# SUBTITLE SUMMARY
Write-Host ""
Write-Host "=== SUBTITLE SUMMARY ===" -ForegroundColor Cyan
$UploadedSubtitles = @()
if ($null -ne $Info.subtitles) {
    $UploadedSubtitles = @($Info.subtitles.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
}
$AutoSubtitles = @()
if ($null -ne $Info.automatic_captions) {
    $AutoSubtitles = @($Info.automatic_captions.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
}
if ($UploadedSubtitles.Count -eq 0 -and $AutoSubtitles.Count -eq 0) {
    Write-Host "None"
}
else {
    if ($UploadedSubtitles.Count -gt 0) { Write-Host "Uploaded: $($UploadedSubtitles -join ', ')" }
    if ($AutoSubtitles.Count -gt 0) { Write-Host "Auto   : $($AutoSubtitles -join ', ')" }
}

# Select best audio per language
$Selected = @()
$Groups = $AudioFormats | Group-Object {
    if ($_.language) { [string]$_.language } else { "und" }
}
foreach ($g in $Groups) {
    $best = $g.Group |
        Sort-Object `
            @{ Expression = { if ($_.abr) { [double]$_.abr } else { 0 } }; Descending = $true },
            @{ Expression = { if ($_.asr) { [double]$_.asr } else { 0 } }; Descending = $true } |
        Select-Object -First 1
    if ($null -ne $best) {
        $lang = if ($best.language) { [string]$best.language } else { "und" }
        $Selected += [PSCustomObject]@{
            Source = "GENERIC"; Language = $lang; FormatId = [string]$best.format_id
        }
    }
}

$Lines = @(foreach ($A in $Selected) { "$($A.Source)|$($A.Language)|$($A.FormatId)" })
if ($null -eq $Lines) { $Lines = @() }
Set-Content -LiteralPath $SelectionFile -Value $Lines -Encoding UTF8

Write-Host ""
Write-Host "=== SELECTED AUDIO ===" -ForegroundColor Cyan
if ($Selected.Count -eq 0) {
    Write-Host "(none — download will use ba*)"
}
else {
    foreach ($A in $Selected) {
        Write-Host "$($A.Source.PadRight(10)) $($A.Language.PadRight(10)) $($A.FormatId)"
    }
}

Write-Host ""
Write-Host "Download dir   : $DownloadDir"
Write-Host "Raw JSON       : $RawJson"
Write-Host "Selection file : $SelectionFile"
Write-Host "QUERY COMPLETE" -ForegroundColor Green

[PSCustomObject]@{
    VideoId       = $VideoId
    PlaylistTitle = $PlaylistTitle
    UploadDate    = $UploadDate
    IsPlaylist    = $IsPlaylist
    DownloadDir   = $DownloadDir
    JsonDir       = $JsonDir
    RawJson       = $RawJson
    SelectionFile = $SelectionFile
}
