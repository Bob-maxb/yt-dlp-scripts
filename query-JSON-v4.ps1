param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$PlaylistTitle = "",

    [ValidateSet("Movie", "Phonics")]
    [string]$Mode = "Movie"

)
$ErrorActionPreference = "Stop"



$YtDlp = "D:\yt-dlp\yt-dlp.exe"

if ($Mode -eq "Phonics") {
    $BaseDir = "D:\10 Learning\English\Phonics"
}
else {
    $BaseDir = "D:\03 Media\Movies & TV"
}
function Get-SafeFolderName {
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return "Single Files"
    }

    # 替换 Windows 文件夹非法字符
    $Safe = $Name -replace '[<>:"/\\|?*]', '_'

    # 去掉结尾的空格和句点
    $Safe = $Safe.TrimEnd(' ', '.')

    if ([string]::IsNullOrWhiteSpace($Safe)) {
        return "Single Files"
    }

    return $Safe
}

Write-Host ""
Write-Host "=== QUERY VIDEO ===" -ForegroundColor Cyan
Write-Host $Url
Write-Host ""

$YtArgs = @(
    "--no-warnings"
    "--skip-download"
    "--dump-single-json"
    "--ignore-no-formats-error"
    "--cookies", "D:\yt-dlp\cookies.txt"
    "--remote-components", "ejs:github"
    "--extractor-args", "youtube:player_client=default,web_embedded;skip=translated_subs"
    $Url
)

$JsonText = & $YtDlp @YtArgs 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: yt-dlp query failed." -ForegroundColor Red
    $JsonText
    exit 1
}

$Start = $JsonText.IndexOf("{")

if ($Start -lt 0) {
    Write-Host "ERROR: JSON not found." -ForegroundColor Red
    exit 1
}

$JsonText = $JsonText.Substring($Start)

try {
    $Info = $JsonText | ConvertFrom-Json
}
catch {
    Write-Host "ERROR: JSON parse failed." -ForegroundColor Red
    exit 1
}

$VideoId = $Info.id

if ([string]::IsNullOrWhiteSpace($VideoId)) {
    Write-Host "ERROR: Video ID not found." -ForegroundColor Red
    exit 1
}

# ========================================
# 确定最终下载目录
# ========================================

$InfoPlaylistTitle = [string]$Info.playlist_title
$UploadDate = [string]$Info.upload_date

# Playlist 模式由 download-movie.ps1 显式传入 PlaylistTitle
if (-not [string]::IsNullOrWhiteSpace($PlaylistTitle)) {
    $IsPlaylist = $true
}
else {
    $IsPlaylist = $false
}


if ($UploadDate -match '^(\d{4})(\d{2})(\d{2})$') {
    $DateFolder = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
}
else {
    Write-Host ""
    Write-Host "ERROR: upload_date not found or invalid: $UploadDate" -ForegroundColor Red
    exit 1
}

# 视频标题：Single / Playlist 两种模式都需要

$VideoTitle = Get-SafeFolderName $Info.title

if ([string]::IsNullOrWhiteSpace($PlaylistTitle)) {

    # ========================================
    # Single File
    # D:\03 Media\Movies & TV\Single Files\
    #     视频标题\
    # ========================================


    $DownloadDir = Join-Path $BaseDir "Single Files"
    $DownloadDir = Join-Path $DownloadDir $VideoTitle

    $IsPlaylist = $false
}



else {

    # ========================================
    # Playlist
    # D:\03 Media\Movies & TV\Playlist\
    #     Playlist名称\
    # ========================================

    $PlaylistFolder = Get-SafeFolderName $PlaylistTitle

    if ($Mode -eq "Phonics") {

        # Phonics:
        # D:\10 Learning\English\Phonics\
        #   Alphabet Unit Resources (1-34)\
        #       The Alphabet Unit_ Lessons 1-34

        $DownloadDir = Join-Path $BaseDir $PlaylistFolder

    }
    else {

        # Movie:
        # D:\03 Media\Movies & TV\
        #   Playlist\
        #       Playlist Name

        $DownloadDir = Join-Path $BaseDir "Playlist"
        $DownloadDir = Join-Path $DownloadDir $PlaylistFolder

    }

    $IsPlaylist = $true

}

$JsonDir = Join-Path $DownloadDir "json"

New-Item -ItemType Directory -Force -Path $JsonDir | Out-Null

# ========================================
# JSON 文件路径
# ========================================

$FileBaseName = "$VideoTitle - $UploadDate"

$RawJson = Join-Path $JsonDir "$FileBaseName.info.json"
$SelectionFile = Join-Path $JsonDir "$FileBaseName.audio-selection.txt"

$JsonText | Set-Content -LiteralPath $RawJson -Encoding UTF8



# ========================================
# 查找 Opus 音频
# ========================================

$AudioFormats = @(
    $Info.formats |
    Where-Object {
        $_.acodec -like "opus*" -and 
        $_.vcodec -eq "none"
    }
)


# 无 Opus 时：退而求其次，用纯 AAC / m4a 音轨
if ($AudioFormats.Count -eq 0) {
    $AudioFormats = @(
        $Info.formats |
        Where-Object {
            $_.vcodec -eq "none" -and
            $_.acodec -and
            $_.acodec -ne "none" -and (
                $_.acodec -like "mp4a*" -or
                $_.acodec -like "aac*"
            )
        }
    )
    if ($AudioFormats.Count -gt 0) {
        Write-Host "WARNING: No Opus; using AAC audio tracks." -ForegroundColor Yellow
    }
}



Write-Host "Video ID       : $VideoId"
Write-Host "Playlist       : $PlaylistTitle"
Write-Host "Download dir   : $DownloadDir"
Write-Host "Audio formats  : $($AudioFormats.Count)"


# ========================================
# VIDEO FORMAT SUMMARY
# 仅显示，不参与格式选择
# ========================================

Write-Host ""
Write-Host "=== VIDEO FORMAT SUMMARY ===" -ForegroundColor Cyan

$VideoFormats = @(
    $Info.formats |
    Where-Object {
        $_.vcodec -and
        $_.vcodec -ne "none"
    } |
    Sort-Object `
        @{Expression = { if ($_.height) { [int]$_.height } else { 0 } }; Descending = $true },
        @{Expression = { if ($_.fps) { [double]$_.fps } else { 0 } }; Descending = $true }
)

if ($VideoFormats.Count -eq 0) {

    Write-Host "None"

}
else {




$VideoFormats | ForEach-Object {
    $Resolution = if ($_.width -and $_.height) { "$($_.width)x$($_.height)" } else { "-" }
    $FPS        = if ($_.fps) { "$($_.fps)" } else { "-" }
    $Type       = if ($_.acodec -and $_.acodec -ne "none") { "video+audio" } else { "video-only" }

    # VBR
    $Vbr = "-"
    if ($_.vbr) {
        $Vbr = "{0:N0}k" -f [double]$_.vbr
    }
    elseif ($_.tbr) {
        $Vbr = "~{0:N0}k" -f [double]$_.tbr
    }

    # FILESIZE
    $Size = "-"
    if ($_.filesize) {
        $bytes = [double]$_.filesize
        if ($bytes -ge 1GB) {
            $Size = "{0:N2} GiB" -f ($bytes / 1GB)
        }
        else {
            $Size = "{0:N1} MiB" -f ($bytes / 1MB)
        }
    }
    elseif ($_.filesize_approx) {
        $bytes = [double]$_.filesize_approx
        if ($bytes -ge 1GB) {
            $Size = "~{0:N2} GiB" -f ($bytes / 1GB)
        }
        else {
            $Size = "~{0:N1} MiB" -f ($bytes / 1MB)
        }
    }

    # HDR
    $Hdr = "-"
    if ($_.dynamic_range) {
        $Hdr = [string]$_.dynamic_range
    }
    elseif ($_.format_note -match '(?i)hdr') {
        $Hdr = "HDR"
    }
    elseif ($_.vcodec -match '(?i)hdr') {
        $Hdr = "HDR"
    }
    else {
        $Hdr = "SDR"
    }

    [PSCustomObject]@{
        ID         = $_.format_id
        CODEC      = $_.vcodec
        RESOLUTION = $Resolution
        FPS        = $FPS
        VBR        = $Vbr
        SIZE       = $Size
        HDR        = $Hdr
        TYPE       = $Type
    }
} | Format-Table -AutoSize | Out-Host








}


# ========================================
# SUBTITLE SUMMARY
# 仅显示，不参与字幕选择
# ========================================

Write-Host ""
Write-Host "=== SUBTITLE SUMMARY ===" -ForegroundColor Cyan

$UploadedSubtitles = @()

if ($null -ne $Info.subtitles) {

    $UploadedSubtitles = @(
        $Info.subtitles.PSObject.Properties |
        ForEach-Object {
            $_.Name
        } |
        Sort-Object
    )
}

$AutoSubtitles = @()

if ($null -ne $Info.automatic_captions) {

    $AutoSubtitles = @(
        $Info.automatic_captions.PSObject.Properties |
        ForEach-Object {
            $_.Name
        } |
        Sort-Object
    )
}

if ($UploadedSubtitles.Count -eq 0 -and $AutoSubtitles.Count -eq 0) {

    Write-Host "None"

}
else {

if ($UploadedSubtitles.Count -gt 0) {
    Write-Host "Uploaded:"
    Write-Host "  $($UploadedSubtitles -join ', ')"
}

if ($AutoSubtitles.Count -gt 0) {
    Write-Host "Auto-generated:"
    Write-Host "  $($AutoSubtitles -join ', ')"
}
}


if ($AudioFormats.Count -eq 0) {
    Write-Host ""
    Write-Host "WARNING: No Opus audio formats found. Generic audio fallback will be used." -ForegroundColor Yellow
}

# ========================================
# 判断音频来源
# ========================================

$Candidates = foreach ($F in $AudioFormats) {

    $Source = "UNKNOWN"
    $XtTags = ""

    if ($F.url) {

        try {
            $DecodedUrl = [System.Uri]::UnescapeDataString([string]$F.url)
        }
        catch {
            $DecodedUrl = [string]$F.url
        }

        if ($DecodedUrl -match "xtags=([^&]+)") {

            $XtTags = $Matches[1]

            try {
                $XtTags = [System.Uri]::UnescapeDataString($XtTags)
            }
            catch {}

        }

        if ($XtTags -match "acont=original") {
            $Source = "ORIGINAL"
        }
        elseif ($XtTags -match "acont=dubbed-auto") {
            $Source = "DUBBED-AUTO"
        }
        elseif ($XtTags -match "acont=dubbed") {
            $Source = "DUBBED"
        }
    }

    [PSCustomObject]@{
        FormatId = [string]$F.format_id
        Language = [string]$F.language
        Source   = $Source
        Abr      = if ($null -ne $F.abr) { [double]$F.abr } else { 0 }
        Asr      = if ($null -ne $F.asr) { [double]$F.asr } else { 0 }
        DRC      = ([string]$F.format_note -match "DRC")
        Note     = [string]$F.format_note
    }
}

# ========================================
# 每个 SOURCE + LANGUAGE 选择最佳 Opus
# ========================================

$Selected = @()

$Groups = $Candidates | Group-Object Source, Language

foreach ($Group in $Groups) {

    $Best = $Group.Group |
        Sort-Object `
            @{Expression = { if ($_.DRC) { 0 } else { 1 } }; Descending = $true}, `
            @{Expression = { $_.Abr }; Descending = $true}, `
            @{Expression = { $_.Asr }; Descending = $true} |
        Select-Object -First 1

    $Selected += $Best
}

$Selected = $Selected |
    Sort-Object @{
        Expression = {
            if ($_.FormatId -match '-(\d+)$') {
                [int]$Matches[1]
            }
            else {
                [int]::MaxValue
            }
        }
    }

# ========================================
# 显示语言摘要
# ========================================

Write-Host ""
Write-Host "=== AUDIO LANGUAGE SUMMARY ==="
Write-Host ""

$Candidates |
    Format-Table `
        @{Label="FORMAT"; Expression={$_.FormatId}},
        @{Label="LANGUAGE"; Expression={$_.Language}},
        @{Label="SOURCE"; Expression={$_.Source}},
        @{Label="ABR"; Expression={$_.Abr}},
        @{Label="DRC"; Expression={$_.DRC}} `
    -AutoSize |
    Out-Host

$OriginalLanguages = @(
    $Candidates |
        Where-Object {
            $_.Source -eq "ORIGINAL" -and $_.Language
        } |
        Select-Object -ExpandProperty Language -Unique
)

$DubbedLanguages = @(
    $Candidates |
        Where-Object {
            $_.Source -eq "DUBBED" -and $_.Language
        } |
        Select-Object -ExpandProperty Language -Unique
)

$DubbedAutoLanguages = @(
    $Candidates |
        Where-Object {
            $_.Source -eq "DUBBED-AUTO" -and $_.Language
        } |
        Select-Object -ExpandProperty Language -Unique
)

$UnknownLanguages = @(
    $Candidates |
        Where-Object {
            $_.Source -eq "UNKNOWN"
        } |
        ForEach-Object {
            if ($_.Language) {
                $_.Language
            }
            else {
                "UNKNOWN"
            }
        } |
        Select-Object -Unique
)

$OriginalText = if ($OriginalLanguages.Count -gt 0) {
    $OriginalLanguages -join ", "
}
else {
    "None"
}

$DubbedText = if ($DubbedLanguages.Count -gt 0) {
    $DubbedLanguages -join ", "
}
else {
    "None"
}

$DubbedAutoText = if ($DubbedAutoLanguages.Count -gt 0) {
    $DubbedAutoLanguages -join ", "
}
else {
    "None"
}

$UnknownCount = @(
    $Candidates |
        Where-Object {
            $_.Source -eq "UNKNOWN"
        }
).Count

$UnknownText = if ($UnknownCount -gt 0) {

    if ($UnknownLanguages.Count -gt 0) {
        "$($UnknownLanguages -join ', ') ($UnknownCount)"
    }
    else {
        "UNKNOWN ($UnknownCount)"
    }

}
else {
    "None"
}

Write-Host "Original languages      : $OriginalText"
Write-Host "Dubbed languages        : $DubbedText"
Write-Host "Dubbed-Auto languages   : $DubbedAutoText"
Write-Host "Unknown languages       : $UnknownText"
Write-Host ""
Write-Host "Total audio streams     : $($Candidates.Count)"

# ========================================
# 保存音频选择
# ========================================

#$Lines = foreach ($A in $Selected) { 
#    if ($A.Source -eq "DUBBED-AUTO") {
#        continue
#    }

#    "$($A.Source)|$($A.Language)|$($A.FormatId)" 
# } 
 
# $Lines | Set-Content -LiteralPath $SelectionFile -Encoding UTF8

# $Lines = @(
#     foreach ($A in $Selected) {  
#         if ($A.Source -eq "DUBBED-AUTO") { 
#             continue 
#         } 
 
#         "$($A.Source)|$($A.Language)|$($A.FormatId)"  
#     }
# )

# $Lines | Set-Content -LiteralPath $SelectionFile -Encoding UTF8



$Lines = @(
    foreach ($A in $Selected) {
        if ($A.Source -eq "DUBBED-AUTO") {
            continue
        }
        "$($A.Source)|$($A.Language)|$($A.FormatId)"
    }
)

if ($null -eq $Lines) { $Lines = @() }

# 空数组也会创建文件，避免主脚本报 Selection file not found
Set-Content -LiteralPath $SelectionFile -Value $Lines -Encoding UTF8





# ========================================
# 显示最终选择
# ========================================

Write-Host ""
Write-Host "=== SELECTED AUDIO ===" -ForegroundColor Cyan

foreach ($A in $Selected) {
    Write-Host "$($A.Source.PadRight(14)) $($A.Language.PadRight(12)) $($A.FormatId)"
}

Write-Host ""
Write-Host "Download dir   : $DownloadDir"
Write-Host "Raw JSON       : $RawJson"
Write-Host "Selection file : $SelectionFile"
Write-Host ""
Write-Host "QUERY COMPLETE" -ForegroundColor Green

# ========================================
# 返回给 download-movie.ps1
# ========================================

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