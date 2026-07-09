# PowerShell WinForms launcher for LPRTool v2.
# Opens a desktop UI that wraps scripts/New-LprFirmwareBatch.ps1.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

function Get-GeneratorPath {
    $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $candidates = @(
        (Join-Path $root "New-LprFirmwareBatch.ps1"),
        (Join-Path $root "scripts\New-LprFirmwareBatch.ps1"),
        (Join-Path (Split-Path $root -Parent) "scripts\New-LprFirmwareBatch.ps1")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw "Generator script not found. Expected New-LprFirmwareBatch.ps1 beside the GUI or under a scripts folder."
}

function Write-OutputText {
    param([string]$Text)
    $outputBox.Text = $Text
}

function Get-BatchFileName {
    $name = $batchBox.Text.Trim()
    if (-not $name.ToLower().EndsWith(".bat")) {
        $name = "$name.bat"
    }
    return $name
}

function Get-ManualRunCommand {
    $folder = $outBox.Text.Trim()
    $batch = Get-BatchFileName
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($batch)
    $errorLog = "${baseName}_Errors.txt"
    return "Set-Location -LiteralPath `"$folder`"`r`ncmd /c `"$batch >> $errorLog 2>&1`""
}

function Test-FormInputs {
    $missing = @()
    if ([string]::IsNullOrWhiteSpace($csvBox.Text)) { $missing += "CSV file" }
    if ([string]::IsNullOrWhiteSpace($fwBox.Text)) { $missing += "Firmware/package file" }
    if ([string]::IsNullOrWhiteSpace($outBox.Text)) { $missing += "Output folder" }
    if ([string]::IsNullOrWhiteSpace($batchBox.Text)) { $missing += "Batch file name" }
    if ([string]::IsNullOrWhiteSpace($queueBox.Text)) { $missing += "LPR queue" }

    if ($missing.Count -gt 0) {
        Write-OutputText "Missing: $($missing -join ', ')"
        return $false
    }
    if (-not (Test-Path -LiteralPath $csvBox.Text)) {
        Write-OutputText "CSV file not found:`r`n$($csvBox.Text)"
        return $false
    }
    if (-not (Test-Path -LiteralPath $fwBox.Text)) {
        Write-OutputText "Firmware/package file not found:`r`n$($fwBox.Text)"
        return $false
    }
    return $true
}

function Invoke-LprTool {
    param([switch]$WritePackage)

    if (-not (Test-FormInputs)) { return }

    try {
        $params = @{
            CsvPath       = $csvBox.Text
            FirmwarePath  = $fwBox.Text
            OutputFolder  = $outBox.Text
            BatchFileName = $batchBox.Text
            LprQueue      = $queueBox.Text
        }
        if ($WritePackage) {
            $params.SkipDryRun = $true
        }

        $scriptPath = Get-GeneratorPath
        $result = & $scriptPath @params 2>&1 | Out-String
        if ($WritePackage) {
            $result = $result + "`r`nManual run command:`r`n" + (Get-ManualRunCommand)
        }
        Write-OutputText $result
    } catch {
        Write-OutputText "Error:`r`n$($_.Exception.Message)"
    }
}

function Set-DialogPath {
    param(
        [System.Windows.Forms.TextBox]$Target,
        [string]$Filter
    )
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = $Filter
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Target.Text = $dialog.FileName
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "LPRTool"
$form.Size = New-Object System.Drawing.Size(760, 620)
$form.StartPosition = "CenterScreen"

$font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Font = $font

$csvLabel = New-Object System.Windows.Forms.Label
$csvLabel.Text = "CSV file of printer IPs (first column is used)"
$csvLabel.Location = New-Object System.Drawing.Point(14, 18)
$csvLabel.Size = New-Object System.Drawing.Size(500, 22)
$form.Controls.Add($csvLabel)

$csvBox = New-Object System.Windows.Forms.TextBox
$csvBox.Location = New-Object System.Drawing.Point(14, 42)
$csvBox.Size = New-Object System.Drawing.Size(610, 24)
$form.Controls.Add($csvBox)

$csvBtn = New-Object System.Windows.Forms.Button
$csvBtn.Text = "Browse"
$csvBtn.Location = New-Object System.Drawing.Point(636, 40)
$csvBtn.Size = New-Object System.Drawing.Size(90, 28)
$csvBtn.Add_Click({ Set-DialogPath -Target $csvBox -Filter "CSV files (*.csv)|*.csv|All files (*.*)|*.*" })
$form.Controls.Add($csvBtn)

$fwLabel = New-Object System.Windows.Forms.Label
$fwLabel.Text = "Firmware or package file"
$fwLabel.Location = New-Object System.Drawing.Point(14, 76)
$fwLabel.Size = New-Object System.Drawing.Size(500, 22)
$form.Controls.Add($fwLabel)

$fwBox = New-Object System.Windows.Forms.TextBox
$fwBox.Location = New-Object System.Drawing.Point(14, 100)
$fwBox.Size = New-Object System.Drawing.Size(610, 24)
$form.Controls.Add($fwBox)

$fwBtn = New-Object System.Windows.Forms.Button
$fwBtn.Text = "Browse"
$fwBtn.Location = New-Object System.Drawing.Point(636, 98)
$fwBtn.Size = New-Object System.Drawing.Size(90, 28)
$fwBtn.Add_Click({
    Set-DialogPath -Target $fwBox -Filter "Firmware/package files (*.dlm;*.weblet;*.rfu;*.pkg;*.hex;*.vme)|*.dlm;*.weblet;*.rfu;*.pkg;*.hex;*.vme|All files (*.*)|*.*"
})
$form.Controls.Add($fwBtn)

$outLabel = New-Object System.Windows.Forms.Label
$outLabel.Text = "Output folder"
$outLabel.Location = New-Object System.Drawing.Point(14, 134)
$outLabel.Size = New-Object System.Drawing.Size(500, 22)
$form.Controls.Add($outLabel)

$outBox = New-Object System.Windows.Forms.TextBox
$outBox.Location = New-Object System.Drawing.Point(14, 158)
$outBox.Size = New-Object System.Drawing.Size(610, 24)
$form.Controls.Add($outBox)

$outBtn = New-Object System.Windows.Forms.Button
$outBtn.Text = "Choose"
$outBtn.Location = New-Object System.Drawing.Point(636, 156)
$outBtn.Size = New-Object System.Drawing.Size(90, 28)
$outBtn.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $outBox.Text = $dialog.SelectedPath
    }
})
$form.Controls.Add($outBtn)

$batchLabel = New-Object System.Windows.Forms.Label
$batchLabel.Text = "Batch file name"
$batchLabel.Location = New-Object System.Drawing.Point(14, 192)
$batchLabel.Size = New-Object System.Drawing.Size(180, 22)
$form.Controls.Add($batchLabel)

$batchBox = New-Object System.Windows.Forms.TextBox
$batchBox.Text = "push_firmware"
$batchBox.Location = New-Object System.Drawing.Point(14, 216)
$batchBox.Size = New-Object System.Drawing.Size(260, 24)
$form.Controls.Add($batchBox)

$queueLabel = New-Object System.Windows.Forms.Label
$queueLabel.Text = "LPR queue"
$queueLabel.Location = New-Object System.Drawing.Point(300, 192)
$queueLabel.Size = New-Object System.Drawing.Size(120, 22)
$form.Controls.Add($queueLabel)

$queueBox = New-Object System.Windows.Forms.TextBox
$queueBox.Text = "lp"
$queueBox.Location = New-Object System.Drawing.Point(300, 216)
$queueBox.Size = New-Object System.Drawing.Size(120, 24)
$form.Controls.Add($queueBox)

$dryRunBtn = New-Object System.Windows.Forms.Button
$dryRunBtn.Text = "Dry Run"
$dryRunBtn.Location = New-Object System.Drawing.Point(14, 256)
$dryRunBtn.Size = New-Object System.Drawing.Size(120, 34)
$dryRunBtn.BackColor = [System.Drawing.Color]::LightSteelBlue
$dryRunBtn.Add_Click({ Invoke-LprTool })
$form.Controls.Add($dryRunBtn)

$writeBtn = New-Object System.Windows.Forms.Button
$writeBtn.Text = "Write Package"
$writeBtn.Location = New-Object System.Drawing.Point(146, 256)
$writeBtn.Size = New-Object System.Drawing.Size(140, 34)
$writeBtn.BackColor = [System.Drawing.Color]::LightGreen
$writeBtn.Add_Click({ Invoke-LprTool -WritePackage })
$form.Controls.Add($writeBtn)

$openBtn = New-Object System.Windows.Forms.Button
$openBtn.Text = "Open Output Folder"
$openBtn.Location = New-Object System.Drawing.Point(300, 256)
$openBtn.Size = New-Object System.Drawing.Size(150, 34)
$openBtn.Add_Click({
    if (Test-Path -LiteralPath $outBox.Text) {
        Start-Process explorer.exe $outBox.Text
    }
})
$form.Controls.Add($openBtn)

$copyBtn = New-Object System.Windows.Forms.Button
$copyBtn.Text = "Copy Run Command"
$copyBtn.Location = New-Object System.Drawing.Point(464, 256)
$copyBtn.Size = New-Object System.Drawing.Size(120, 34)
$copyBtn.Add_Click({
    if ([string]::IsNullOrWhiteSpace($outBox.Text) -or [string]::IsNullOrWhiteSpace($batchBox.Text)) {
        Write-OutputText "Output folder and batch file name are required before copying the run command."
        return
    }
    [System.Windows.Forms.Clipboard]::SetText((Get-ManualRunCommand))
    Write-OutputText "Copied manual run command:`r`n$(Get-ManualRunCommand)"
})
$form.Controls.Add($copyBtn)

$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Multiline = $true
$outputBox.ScrollBars = "Vertical"
$outputBox.WordWrap = $true
$outputBox.Location = New-Object System.Drawing.Point(14, 306)
$outputBox.Size = New-Object System.Drawing.Size(712, 250)
$outputBox.Text = "Choose files, then click Dry Run. Write Package creates the batch, manifest, error-log stub, and zip."
$form.Controls.Add($outputBox)

$form.Topmost = $false
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
