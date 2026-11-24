<#
.SYNOPSIS
    100% Portable Laptop Quality Control Diagnostic Suite & PDF Auto-Stamper
.DESCRIPTION
    Runs hardware audits directly from USB, executes interactive user tests, 
    and stamps specs and checkmarks onto QC_Template.pdf with exact calibrated coordinates.
#>

# Check Administrator Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Running without Administrator privileges. Please run as Administrator for full diagnostic access."
}

# Dynamically detect USB Directory
$usbPath = $PSScriptRoot
if (-not $usbPath) { $usbPath = Get-Location }
$templatePdf = Join-Path $usbPath "QC_Template.pdf"

# Process DPI Awareness for native resolution detection
$dpiCode = @"
using System;
using System.Runtime.InteropServices;
public class NativeDPI {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
Add-Type -TypeDefinition $dpiCode -ErrorAction SilentlyContinue
[NativeDPI]::SetProcessDPIAware()

Clear-Host
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "       STARTING PORTABLE LAPTOP QUALITY CONTROL & SPEC AUDIT              " -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "USB Working Directory: $usbPath" -ForegroundColor DarkCyan
Write-Host ""

# Helper function for interactive user test prompts
function Prompt-UserCheck ([string]$testName) {
    while ($true) {
        $inputVal = Read-Host "$testName -> [P]ass / [F]ail / [S]kip"
        if ($inputVal -eq 'P' -or $inputVal -eq 'p') { return "PASS" }
        if ($inputVal -eq 'F' -or $inputVal -eq 'f') { return "FAIL" }
        if ($inputVal -eq 'S' -or $inputVal -eq 's') { return "NOT_TESTED" }
        Write-Host "Invalid input. Type P for Pass, F for Fail, or S for Skip." -ForegroundColor Red
    }
}

# ---------------------------------------------------------
# 1. HARDWARE SPECIFICATIONS AUDIT (INTERNAL DISKS ONLY)
# ---------------------------------------------------------
Write-Host "`n[1/4] Auto-Auditing System Specs & Internal Storage..." -ForegroundColor Yellow

$bios  = Get-CimInstance -ClassName Win32_BIOS
$sys   = Get-CimInstance -ClassName Win32_ComputerSystem
$cpu   = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
$os    = Get-CimInstance -ClassName Win32_OperatingSystem

$brand = $sys.Manufacturer
$model = $sys.Model

# RAM Calculation
$ramModules = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue
if ($ramModules) {
    $ramMB = ($ramModules | Measure-Object -Property Capacity -Sum).Sum / 1MB
} else {
    $ramMB = $sys.TotalPhysicalMemory / 1MB
}
$ramGB = [math]::Round($ramMB / 1024)

# Storage Calculation (EXCLUDES USB Drives)
$internalDisks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue | Where-Object { 
    $_.InterfaceType -ne "USB" -and $_.MediaType -match "Fixed"
}
$totalStorageGB = 0
foreach ($d in $internalDisks) { $totalStorageGB += [math]::Round($d.Size / 1GB) }

# Display Resolution & GPU
Add-Type -AssemblyName System.Windows.Forms
$gpuObj = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.CurrentHorizontalResolution -gt 0 } | Select-Object -First 1
if ($gpuObj) {
    $actualResWidth  = $gpuObj.CurrentHorizontalResolution
    $actualResHeight = $gpuObj.CurrentVerticalResolution
    $gpuName         = $gpuObj.Name
} else {
    $primaryScreen   = [System.Windows.Forms.Screen]::PrimaryScreen
    $actualResWidth  = $primaryScreen.Bounds.Width
    $actualResHeight = $primaryScreen.Bounds.Height
    $gpuName         = "Generic Display Adapter"
}
$actualResStr = "$actualResWidth x $actualResHeight"

$resRecordedStatus = "PASS"
$resStandardStatus = if ($actualResStr -eq "1920 x 1080" -or $actualResStr -eq "3840 x 2160") { "PASS" } else { "FAIL" }
$gpuCardStatus     = if ($gpuObj) { "PASS" } else { "FAIL" }

# Touchscreen Detection
$touchDevice = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { 
    ($_.FriendlyName -match "Touch Screen|HID-compliant touch screen" -or $_.Class -eq "Touchscreen") -and $_.Status -eq "OK" 
}
$hasTouchscreen = [bool]$touchDevice

# Operating System Check
$win11Status    = if ($os.Caption -like "*Windows 11*") { "PASS" } else { "FAIL" }
$win11ProStatus = if ($os.Caption -like "*Pro*") { "PASS" } else { "FAIL" }

# Wi-Fi Connectivity Check
$wifiAdapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.MediaType -like "*802.11*" -or $_.Name -like "*Wi-Fi*" }
$wifiPass    = if ($wifiAdapter -and (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet)) { "PASS" } else { "FAIL" }

# ---------------------------------------------------------
# 2. BATTERY HEALTH EVALUATION
# ---------------------------------------------------------
Write-Host "`n[2/4] Auto-Evaluating Battery Health..." -ForegroundColor Yellow

$batStatic = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue
$batFull   = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue

$batGood = $false; $batFair = $false; $batPoor = $false
if ($batStatic -and $batFull -and $batStatic.DesignedCapacity -gt 0) {
    $pct = [math]::Round(($batFull.FullChargedCapacity / $batStatic.DesignedCapacity) * 100, 1)
    if ($pct -ge 80) { $batGood = $true }
    elseif ($pct -ge 50) { $batFair = $true }
    else { $batPoor = $true }
} else {
    $batGood = $true
}

# ---------------------------------------------------------
# 3. INTERACTIVE HARDWARE TESTS
# ---------------------------------------------------------

# --- DISPLAY TEST ---
Write-Host "`n[3/4] Screen & Display Test" -ForegroundColor Yellow
Read-Host "Press ENTER to launch full-screen color sweep (Press SPACE/ENTER to switch colors, ESC to exit)..."

Add-Type -AssemblyName System.Drawing
$testColors = @([System.Drawing.Color]::Red, [System.Drawing.Color]::Green, [System.Drawing.Color]::Blue, [System.Drawing.Color]::White, [System.Drawing.Color]::Black)

$script:colorIdx = 0
$dispForm = New-Object System.Windows.Forms.Form
$dispForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$dispForm.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
$dispForm.TopMost = $true
$dispForm.BackColor = $testColors[0]

$dispForm.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq 'Escape') { $dispForm.Close() }
    elseif ($e.KeyCode -eq 'Return' -or $e.KeyCode -eq 'Space') {
        $script:colorIdx++
        if ($script:colorIdx -ge $testColors.Count) { $dispForm.Close() } 
        else { $dispForm.BackColor = $testColors[$script:colorIdx] }
    }
})
$dispForm.Add_Click({
    $script:colorIdx++
    if ($script:colorIdx -ge $testColors.Count) { $dispForm.Close() } 
    else { $dispForm.BackColor = $testColors[$script:colorIdx] }
})

[void]$dispForm.ShowDialog()
$dispForm.Dispose()

$deadPixelsPass = Prompt-UserCheck -testName "Screen Visual Check (No dead pixels, lines, spots, or cracks)"

# --- SPEAKERS TEST ---
Write-Host "`nSpeaker Test..." -ForegroundColor Yellow
try {
    $synth = New-Object -ComObject SAPI.SpVoice
    $synth.Speak("Testing left and right audio speakers.")
    [Console]::Beep(440, 200)
    [Console]::Beep(880, 200)
} catch {}
$speakerPass = Prompt-UserCheck -testName "Speakers Test (Did audio sound clear?)"

# --- MICROPHONE TEST ---
Write-Host "`nOpening Microphone Test in Browser..." -ForegroundColor Yellow
Start-Process "msedge.exe" -ArgumentList "--app=`"$((Join-Path $usbPath 'mic-test-offline.html'))`""
$micPass = Prompt-UserCheck -testName "Microphone Test (Did microphone capture audio cleanly?)"

# --- CAMERA TEST ---
Write-Host "`nOpening Camera App..." -ForegroundColor Yellow
try {
    Start-Process "microsoft.windows.camera:"
} catch {
    try { Start-Process "explorer.exe" -ArgumentList "microsoft.windows.camera:" } catch {}
}
$cameraPass = Prompt-UserCheck -testName "Camera Test (Did photo and video capture work?)"

# --- KEYBOARD TEST ---
Write-Host "`nOpening Keyboard Test in Browser..." -ForegroundColor Yellow
Start-Process "msedge.exe" -ArgumentList "--app=`"$((Join-Path $usbPath 'keyboard-tester.html'))`""
$keyboardPass = Prompt-UserCheck -testName "Keyboard Test (Did all keys respond?)"

# --- MANUAL PORT & HARDWARE CHECKS ---
Write-Host "`n--------------------------------------------------------- " -ForegroundColor Yellow
Write-Host "Manual Hardware & Port Verification Prompts:" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------- " -ForegroundColor Yellow

$trackpadPass    = Prompt-UserCheck -testName "Trackpad (Clicking and gesture movement)"
$touchscreenPass = if ($hasTouchscreen) { Prompt-UserCheck -testName "Touchscreen (Touch response)" } else { "NOT_TESTED" }
$fingerprintPass = Prompt-UserCheck -testName "Fingerprint Reader"
$chargingPass    = Prompt-UserCheck -testName "Charging Port"
$usbAPass        = Prompt-UserCheck -testName "USB-A Ports"
$usbCPass        = Prompt-UserCheck -testName "USB-C Ports"
$hdmiPass        = Prompt-UserCheck -testName "HDMI / External Video"
$bluetoothPass   = Prompt-UserCheck -testName "Bluetooth Connection"

# ---------------------------------------------------------
# 4. EXACT STAMPING ON PDF CANVAS USING VERIFIED COORDINATES
# ---------------------------------------------------------
Write-Host "`n[4/4] Stamping Text and Checkmarks onto PDF Canvas..." -ForegroundColor Cyan

# Creating dictionary
$recap = @{}
pdftk $templatePdf dump_data_fields_utf8 | findstr FieldName | ForEach-Object { 
	$key = $_ -replace 'FieldName: ', ''
	$recap[$key] = ""
}

$timestamp   = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$desktopPath = [Environment]::GetFolderPath('Desktop')
$outputPdf   = "$desktopPath\LaptopTest_$timestamp.pdf"

if (-not (Test-Path $templatePdf)) {
    Write-Error "PDF Template file not found at: $templatePdf"
    return
}

try {
    function Write-RowResult ([string]$status, [string]$section, [float]$row) {
        switch ($status) {
            "PASS"       { $recap[$section + "_row" + [string]$row + "_p"] = "Yes" }
            "FAIL"       { $recap[$section + "_row" + [string]$row + "_f"] = "Yes" }
            default      { $recap[$section + "_row" + [string]$row + "_s"] = "Yes" }
        }
    }

    # =========================================================
    # 1. LEFT COLUMN: SECTION 2 (SCREEN & GRAPHICS)
    # =========================================================
    Write-RowResult -status $deadPixelsPass    -section scgr -row 1
    Write-RowResult -status $resRecordedStatus -section scgr -row 2
    Write-RowResult -status $resStandardStatus -section scgr -row 3
    Write-RowResult -status $gpuCardStatus     -section scgr -row 4

    # =========================================================
    # 2. LEFT COLUMN: SECTION 3 (AUDIO & INPUT)
    # =========================================================
    Write-RowResult -status $speakerPass     -section auin -row 1
    Write-RowResult -status $micPass         -section auin -row 2
    Write-RowResult -status $cameraPass      -section auin -row 3
    Write-RowResult -status $keyboardPass    -section auin -row 4
    Write-RowResult -status $trackpadPass    -section auin -row 5
    Write-RowResult -status $touchscreenPass -section auin -row 6
    Write-RowResult -status $fingerprintPass -section auin -row 7

    # =========================================================
    # 3. LEFT COLUMN: SECTION 4 (PORTS & CONNECTIVITY)
    # =========================================================
    Write-RowResult -status $chargingPass   -section poco -row 1
    Write-RowResult -status $usbAPass       -section poco -row 2
    Write-RowResult -status $usbCPass       -section poco -row 3
    Write-RowResult -status $hdmiPass       -section poco -row 4
    Write-RowResult -status $wifiPass       -section poco -row 5
    Write-RowResult -status $bluetoothPass  -section poco -row 6

    # =========================================================
    # 4. LEFT COLUMN: SECTION 5 (OPERATING SYSTEM)
    # =========================================================
# turn this into switch case
    Write-RowResult -status $win11Status    -passX 231 -failX 261 -notTestedX 291 -y 74
    Write-RowResult -status $win11ProStatus -passX 231 -failX 260 -notTestedX 290 -y 53

    # =========================================================
    # 5. RIGHT COLUMN: BRANDS, SPECS & OPTIONS
    # =========================================================
    if ($brand -match "Lenovo") { $recap["lenovo"] = "Yes" }
    if ($brand -match "Dell")   { $recap["dell"] = "Yes" }
    if ($brand -match "HP")     { $recap["hp"] = "Yes" }
    if ($brand -match "Apple")  { $recap["apple"] = "Yes" }

    # Specification Text Fields
    $recap["model"] = $model
    $recap["cpu"] = $cpu.Name
    $recap["memory"] = $ramGB
    $recap["storage"] = $totalStorageGB

    # Password / BIOS Checkbox
    $recap["bios_unlock"] = "Yes" # UNLOCK

    # Screen Condition Checkbox
    if ($deadPixelsPass -eq "PASS") { 
        $recap["screen_good"] = "Yes"
    } else { 
        $recap["screen_pixels"] = "Yes"
    }

    # Touchscreen Checkbox
    if ($hasTouchscreen) { 
        $recap["touch_yes"] = "Yes" # YES
    } else { 
        $recap["touch_no"] = "Yes" # NO
    }

    # Sell status
    # [sell incomplete criteria]
    # [else sell parts]

    # Battery Health Checkbox
    if ($batGood) { 
        $recap["batt_good"] = "Yes" # GOOD
    } elseif ($batFair) { 
        $recap["batt_fair"] = "Yes" # FAIR
    } else { 
        $recap["batt_poor"] = "Yes" # POOR
    }

    # Screen Resolution Checkboxes
    if ($actualResStr -eq "1920 x 1080") {
        $recap["fhd"] = "Yes" # FHD
    } elseif ($actualResStr -eq "3840 x 2160") {
        $recap["uhd"] = "Yes" # UHD / 4K
    } else {
        $recap["scres_other_check"] = "Yes" # OTHER
        $recap["scres_other_text"] = $actualResStr
    }

    # Additional Notes / Serial Info
    $notes = "Serial: $($bios.SerialNumber) | GPU: $gpuName"
    $recap["serial"] = $notes

    # Generating .fdf file
    $fielddata = ""
    foreach ($entry in $recap.GetEnumerator()) {
	$fielddata += "<< /T ($($entry.Key)) /V ($($entry.Value)) >>`n"
    }
    $datafdf = @"
%FDF-1.2
1 0 obj
<< /FDF << /Fields [
    $($fielddata)
] >> >>
endobj
trailer
<< /Root 1 0 R >>
%%EOF
"@

    $datafdf | Out-File -FilePath "./data.fdf" -Encoding utf8
    pdftk $templatePdf fill_form data.fdf output $outputPdf need_appearances
    Remove-Item -Path data.fdf

    Write-Host "`n==========================================================================" -ForegroundColor Green
    Write-Host " SUCCESS! Quality Control PDF filled and saved to Desktop." -ForegroundColor Green
    Write-Host " Saved at: $outputPdf" -ForegroundColor Cyan
    Write-Host "==========================================================================`n" -ForegroundColor Green
} catch {
    Write-Error "Error stamping PDF: $_"
}
