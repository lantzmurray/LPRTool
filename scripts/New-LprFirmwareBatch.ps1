<#
.SYNOPSIS
    LPRTool - builds a reviewable Windows LPR batch file for printer firmware/package pushes.

.DESCRIPTION
    Reads a CSV of printer IPs (first column used), validates each IP, and generates
    a reviewable .bat of direct `LPR -S <ip> -P lp "<firmware>"` commands. The tool
    DOES NOT execute the push - it produces the batch and leaves execution to the
    operator. This is the safety boundary: review first, run second.

    Source-first v2 workflow for reviewable LPR batch generation.

.PARAMETER CsvPath
    CSV file of printer IPs. First column is used; headers/extra columns ignored.
    One IP per row. Blank rows and non-IP values are skipped and reported.

.PARAMETER FirmwarePath
    Path to the firmware/package file (.dlm, .weblet, .rfu, .pkg, .hex, .vme, etc.)
    pushed to each device via LPR.

.PARAMETER OutputFolder
    Folder to write the generated .bat, optional error-log stub, manifest CSV, and zip into.

.PARAMETER BatchFileName
    Name of the generated batch file. .bat extension added if missing.

.PARAMETER LprQueue
    LPR queue name sent with each command. Default: lp.

.PARAMETER DryRun
    Default behavior. Shows what would be generated without writing files.
    Pass -SkipDryRun (or -Execute) to actually write the batch package.

.PARAMETER SkipDryRun
    Alias: Execute. Writes the batch file package (does NOT run it against devices).

.EXAMPLE
    .\New-LprFirmwareBatch.ps1 -CsvPath .\ips.csv -FirmwarePath C:\fw\package.dlm -OutputFolder .\out -BatchFileName push_firmware
    # Dry run - prints the plan, writes nothing.

.EXAMPLE
    .\New-LprFirmwareBatch.ps1 -CsvPath .\ips.csv -FirmwarePath C:\fw\package.dlm -OutputFolder .\out -BatchFileName push_firmware -SkipDryRun
    # Writes push_firmware.bat, push_firmware_Errors.txt (stub), push_firmware_manifest.csv, and push_firmware_package.zip.

.NOTES
    Generated batches target Windows LPR (print services / LPR port monitor). The tool
    does not enable Windows features for you - run the preflight checklist in the output
    if `LPR` is not recognized on the target machine.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [string]$FirmwarePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputFolder,

    [Parameter(Mandatory = $true)]
    [string]$BatchFileName,

    [string]$LprQueue = "lp",

    [switch]$DryRun,

    [Alias("Execute")]
    [switch]$SkipDryRun
)

# Dry run is the default posture. -DryRun is explicit; -SkipDryRun/-Execute opts in to writing files.
$WriteFiles = if ($DryRun) { $false } elseif ($SkipDryRun) { $true } else { $false }

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Test-ValidIp {
    # Strict IPv4 validation: four octets, each 0-255. Rejects 999.x and the like.
    param([string]$Candidate)
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $false }
    if ($Candidate -notmatch '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$') { return $false }
    foreach ($octet in $Candidate.Split('.')) {
        $n = 0
        if (-not [int]::TryParse($octet, [ref]$n)) { return $false }
        if ($n -lt 0 -or $n -gt 255) { return $false }
    }
    return $true
}

function Get-FirmwareKind {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLower()
    switch ($ext) {
        ".dlm"    { if ((Get-Item $Path -ErrorAction SilentlyContinue).Length -gt 50MB) { "DLM Firmware" } else { "DLM Patch/Clone" } }
        ".weblet" { "Weblet Package" }
        ".rfu"    { "Ricoh Firmware" }
        ".pkg"    { "Ricoh/Lexmark Package" }
        ".hex"    { "HP Firmware" }
        ".vme"    { "HP Firmware" }
        default   { "Unknown ($ext)" }
    }
}

function New-DeviceRecord {
    param([string]$Ip, [string]$Status, [string]$Message)
    [pscustomobject]@{
        Ip      = $Ip
        Status  = $Status   # Valid | Skipped | Invalid
        Message = $Message
    }
}

# ---------------------------------------------------------------------------
# Preflight: inputs must exist
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $CsvPath)) {
    throw "CSV file not found: $CsvPath"
}
if (-not (Test-Path -LiteralPath $FirmwarePath)) {
    throw "Firmware file not found: $FirmwarePath"
}

# Firmware path is embedded verbatim into the generated batch - confirm it resolves.
$resolvedFw = (Resolve-Path -LiteralPath $FirmwarePath).Path

# ---------------------------------------------------------------------------
# Read + validate IPs
# ---------------------------------------------------------------------------

$rawRows = @(Get-Content -LiteralPath $CsvPath | Where-Object { $_ -and $_.Trim() })
$records = foreach ($row in $rawRows) {
    # First CSV column only; tolerate headers/extra columns.
    $ip = ($row -split ',')[0].Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($ip)) {
        New-DeviceRecord -Ip "" -Status "Skipped" -Message "Blank row."
        continue
    }
    if (Test-ValidIp -Candidate $ip) {
        New-DeviceRecord -Ip $ip -Status "Valid" -Message ""
    } else {
        New-DeviceRecord -Ip $ip -Status "Invalid" -Message "Not a valid IPv4 address (each octet must be 0-255)."
    }
}

$validIps   = @($records | Where-Object Status -eq 'Valid' | Select-Object -ExpandProperty Ip)
$invalid    = @($records | Where-Object Status -eq 'Invalid')
$validCount = $validIps.Count
$totalCount = $records.Count

# ---------------------------------------------------------------------------
# Resolve output paths
# ---------------------------------------------------------------------------

if (-not $BatchFileName.ToLower().EndsWith(".bat")) {
    $BatchFileName += ".bat"
}
$baseName      = [System.IO.Path]::GetFileNameWithoutExtension($BatchFileName)
$batchPath     = Join-Path $OutputFolder $BatchFileName
$errorLogName  = "${baseName}_Errors.txt"
$manifestName  = "${baseName}_manifest.csv"
$manifestPath  = Join-Path $OutputFolder $manifestName
$zipName       = "${baseName}_package.zip"
$zipPath       = Join-Path $OutputFolder $zipName

# ---------------------------------------------------------------------------
# Dry-run report (default)
# ---------------------------------------------------------------------------

if (-not $WriteFiles) {
    Write-Host ""
    Write-Host "=== LPRTool DRY RUN ===" -ForegroundColor Cyan
    Write-Host "CSV           : $CsvPath"
    Write-Host "Firmware      : $resolvedFw ($(Get-FirmwareKind -Path $resolvedFw))"
    Write-Host "Output folder : $OutputFolder"
    Write-Host "Batch file    : $BatchFileName"
    Write-Host "LPR queue     : $LprQueue"
    Write-Host ""
    Write-Host "Rows read     : $totalCount"
    Write-Host "Valid IPs     : $validCount" -ForegroundColor Green
    if ($invalid.Count -gt 0) {
        Write-Host "Invalid/skipped: $($invalid.Count)" -ForegroundColor Yellow
        $invalid | Format-Table Ip, Status, Message -AutoSize
    }
    if ($validCount -eq 0) {
        Write-Host "No valid IPs to generate. Nothing to write." -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host "Sample commands that would be generated:" -ForegroundColor Cyan
    $validIps | Select-Object -First 5 | ForEach-Object {
        Write-Host "  LPR -S $_ -P $LprQueue `"$resolvedFw`""
    }
    if ($validCount -gt 5) { Write-Host "  ... ($($validCount - 5) more)" }
    Write-Host ""
    Write-Host "Dry run only - nothing written. Re-run with -SkipDryRun (alias -Execute) to write the package." -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------------------
# Write files (operator opted in)
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory | Out-Null
}

if ($validCount -eq 0) {
    Write-Host "No valid IPs to generate. Nothing written." -ForegroundColor Red
    return
}

# Generated batch: intentionally boring. Direct LPR commands only.
# External logging can be added when the operator runs the batch.
$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$header = @(
    "REM ============================================================================"
    "REM LPRTool generated firmware push batch"
    "REM Generated : $timestamp"
    "REM Firmware  : $resolvedFw"
    "REM Devices   : $validCount valid IP(s) out of $totalCount row(s)"
    "REM Queue     : $LprQueue"
    "REM Review each line before running."
    "REM ============================================================================"
    ""
)

$pushLines = foreach ($ip in $validIps) {
    "LPR -S $ip -P $LprQueue `"$resolvedFw`""
}

Set-Content -LiteralPath $batchPath -Value ($header + $pushLines) -Encoding ASCII

# Manifest: per-device record so John can see what was included/excluded.
$records | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding ASCII

# Error-log stub. The generated batch does not write to it internally.
# Use the run command below to capture stdout/stderr externally.
New-Item -Path (Join-Path $OutputFolder $errorLogName) -ItemType File -Force | Out-Null

# Zip the batch + manifest + error-log stub.
Compress-Archive -Path $batchPath, $manifestPath, (Join-Path $OutputFolder $errorLogName) `
                 -DestinationPath $zipPath -Force

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "=== LPRTool batch package written ===" -ForegroundColor Green
Write-Host "Batch     : $batchPath"
Write-Host "Manifest  : $manifestPath  ($validCount valid, $($invalid.Count) invalid/skipped)"
Write-Host "Error log : $(Join-Path $OutputFolder $errorLogName) (stub - use run command below to capture output)"
Write-Host "Zip       : $zipPath"
Write-Host ""
Write-Host "Next step: REVIEW $BatchFileName, then run it from the output folder:" -ForegroundColor Cyan
Write-Host "  cd /d `"$OutputFolder`""
Write-Host "  $BatchFileName >> $errorLogName 2>&1"
Write-Host ""
Write-Host "Preflight if 'LPR' is not recognized:" -ForegroundColor Yellow
Write-Host "  Windows Settings > Apps > Optional features > Add 'Print and Document Services' / LPR port monitor,"
Write-Host "  or: dism /online /enable-feature /featurename:Printing-Foundation-LPRPortMonitor"
if ($invalid.Count -gt 0) {
    Write-Host ""
    Write-Host "Invalid/skipped rows (see manifest for full detail):" -ForegroundColor Yellow
    $invalid | Format-Table Ip, Status, Message -AutoSize
}
