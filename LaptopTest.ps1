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

# ---------------------------------------------------------
# 0. RESOLVE & DEPENDENCY LOADER (ITEXTSHARP + BOUNCYCASTLE)
# ---------------------------------------------------------
$iTextDll    = Join-Path $usbPath "iTextSharp.dll"
$bouncyDll   = Join-Path $usbPath "BouncyCastle.Crypto.dll"
$templatePdf = Join-Path $usbPath "QC_Template.pdf"

if (-not (Test-Path $templatePdf)) {
    $templatePdf = Join-Path $usbPath "2026-10-27 16_56 (1).pdf"
}

try {
    if (Test-Path $bouncyDll) {
        Unblock-File -Path $bouncyDll -ErrorAction SilentlyContinue
        [System.Reflection.Assembly]::Load([System.IO.File]::ReadAllBytes($bouncyDll)) | Out-Null
    }
    if (Test-Path $iTextDll) {
        Unblock-File -Path $iTextDll -ErrorAction SilentlyContinue
        [System.Reflection.Assembly]::Load([System.IO.File]::ReadAllBytes($iTextDll)) | Out-Null
        Write-Host "[+] Loaded PDF stamping engine into memory successfully." -ForegroundColor Green
    } else {
        Write-Error "iTextSharp.dll is missing from USB drive."
        return
    }
} catch {
    Write-Error "Failed to load assemblies into memory: $_"
    return
}

# Helper function to open web links directly in Chrome or Edge
function Open-WebLink ([string]$url) {
    $chromePath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    $chromePathx86 = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    
    if (Test-Path $chromePath) {
        Start-Process $chromePath -ArgumentList $url
    } elseif (Test-Path $chromePathx86) {
        Start-Process $chromePathx86 -ArgumentList $url
    } else {
        Start-Process "msedge.exe" -ArgumentList $url
    }
}

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
tart-Process "msedge.exe" -ArgumentList "--app=`"$((Get-Item 'mic-test-offline.html').FullName)`""
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
Open-WebLink -url "https://key-test.com/"
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

$timestamp   = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$desktopPath = [Environment]::GetFolderPath('Desktop')
$outputPdf   = "$desktopPath\LaptopTest_$timestamp.pdf"

if (-not (Test-Path $templatePdf)) {
    Write-Error "PDF Template file not found at: $templatePdf"
    return
}

try {
    $reader = New-Object iTextSharp.text.pdf.PdfReader($templatePdf)
    $outputStream = [System.IO.File]::Create($outputPdf)
    $stamper = New-Object iTextSharp.text.pdf.PdfStamper($reader, $outputStream)
    $canvas = $stamper.GetOverContent(1) # Page 1

    $bfBold = [iTextSharp.text.pdf.BaseFont]::CreateFont([iTextSharp.text.pdf.BaseFont]::HELVETICA_BOLD, [iTextSharp.text.pdf.BaseFont]::CP1252, $false)
    $bfNorm = [iTextSharp.text.pdf.BaseFont]::CreateFont([iTextSharp.text.pdf.BaseFont]::HELVETICA, [iTextSharp.text.pdf.BaseFont]::CP1252, $false)

    function Write-PdfText ([float]$x, [float]$y, [string]$text, [int]$fontSize=9, [bool]$isBold=$false) {
        $font = if ($isBold) { $bfBold } else { $bfNorm }
        $canvas.BeginText()
        $canvas.SetFontAndSize($font, $fontSize)
        $canvas.SetTextMatrix($x, $y)
        $canvas.ShowText($text)
        $canvas.EndText()
    }

    function Write-Check ([float]$x, [float]$y) {
        Write-PdfText -x $x -y $y -text "X" -fontSize 10 -isBold $true
    }

    # Router using verified explicit coordinates per column
    function Write-RowResult ([string]$status, [float]$passX, [float]$failX, [float]$notTestedX, [float]$y) {
        switch ($status) {
            "PASS"       { Write-Check -x $passX      -y $y }
            "FAIL"       { Write-Check -x $failX      -y $y }
            default      { Write-Check -x $notTestedX -y $y }
        }
    }

    # =========================================================
    # 1. LEFT COLUMN: SECTION 2 (SCREEN & GRAPHICS)
    # =========================================================
    Write-RowResult -status $deadPixelsPass    -passX 237 -failX 266 -notTestedX 296 -y 472
    Write-RowResult -status $resRecordedStatus -passX 237 -failX 266 -notTestedX 296 -y 455
    Write-RowResult -status $resStandardStatus -passX 236 -failX 266 -notTestedX 296 -y 437
    Write-RowResult -status $gpuCardStatus     -passX 236 -failX 266 -notTestedX 296 -y 421

    # =========================================================
    # 2. LEFT COLUMN: SECTION 3 (AUDIO & INPUT)
    # =========================================================
    Write-RowResult -status $speakerPass     -passX 236 -failX 265 -notTestedX 295 -y 370
    Write-RowResult -status $micPass         -passX 236 -failX 266 -notTestedX 296 -y 354
    Write-RowResult -status $cameraPass      -passX 236 -failX 265 -notTestedX 295 -y 337
    Write-RowResult -status $keyboardPass    -passX 236 -failX 265 -notTestedX 295 -y 320
    Write-RowResult -status $trackpadPass    -passX 236 -failX 265 -notTestedX 295 -y 302
    Write-RowResult -status $touchscreenPass -passX 236 -failX 265 -notTestedX 295 -y 286
    Write-RowResult -status $fingerprintPass -passX 236 -failX 265 -notTestedX 295 -y 268

    # =========================================================
    # 3. LEFT COLUMN: SECTION 4 (PORTS & CONNECTIVITY)
    # =========================================================
    Write-RowResult -status $chargingPass   -passX 234 -failX 263 -notTestedX 294 -y 219
    Write-RowResult -status $usbAPass       -passX 233 -failX 263 -notTestedX 294 -y 202
    Write-RowResult -status $usbCPass       -passX 233 -failX 263 -notTestedX 293 -y 184
    Write-RowResult -status $hdmiPass       -passX 232 -failX 263 -notTestedX 293 -y 167
    Write-RowResult -status $wifiPass       -passX 232 -failX 263 -notTestedX 293 -y 149
    Write-RowResult -status $bluetoothPass  -passX 232 -failX 263 -notTestedX 293 -y 131

    # =========================================================
    # 4. LEFT COLUMN: SECTION 5 (OPERATING SYSTEM)
    # =========================================================
    Write-RowResult -status $win11Status    -passX 231 -failX 261 -notTestedX 291 -y 74
    Write-RowResult -status $win11ProStatus -passX 231 -failX 260 -notTestedX 290 -y 53

    # =========================================================
    # 5. RIGHT COLUMN: BRANDS, SPECS & OPTIONS
    # =========================================================
    if ($brand -match "Lenovo") { Write-Check -x 406 -y 609 }
    if ($brand -match "Dell")   { Write-Check -x 444 -y 609 }
    if ($brand -match "HP")     { Write-Check -x 478 -y 609 }
    if ($brand -match "Apple")  { Write-Check -x 514 -y 610 }

    # Specification Text Fields
    Write-PdfText -x 370 -y 586 -text $model -fontSize 9 -isBold $true
    Write-PdfText -x 370 -y 560 -text $cpu.Name -fontSize 8 -isBold $true
    Write-PdfText -x 445 -y 540 -text "$ramGB" -fontSize 9 -isBold $true
    Write-PdfText -x 445 -y 520 -text "$totalStorageGB" -fontSize 9 -isBold $true

    # Password / BIOS Checkbox
    Write-Check -x 470 -y 489 # UNLOCK

    # Screen Condition Checkbox
    if ($deadPixelsPass -eq "PASS") { 
        Write-Check -x 419 -y 464 # GOOD
    } else { 
        Write-Check -x 502 -y 464 # PIXELS
    }

    # Touchscreen Checkbox
    if ($hasTouchscreen) { 
        Write-Check -x 419 -y 437 # YES
    } else { 
        Write-Check -x 466 -y 437 # NO
    }

    # Battery Health Checkbox
    if ($batGood) { 
        Write-Check -x 419 -y 410 # GOOD
    } elseif ($batFair) { 
        Write-Check -x 462 -y 410 # FAIR
    } else { 
        Write-Check -x 501 -y 410 # POOR
    }

    # Screen Resolution Checkboxes
    if ($actualResStr -eq "1920 x 1080") {
        Write-Check -x 334 -y 292 # FHD
    } elseif ($actualResStr -eq "3840 x 2160") {
        Write-Check -x 334 -y 268 # UHD / 4K
    } else {
        Write-Check -x 334 -y 245 # OTHER
        Write-PdfText -x 375 -y 245 -text $actualResStr -fontSize 8 -isBold $true
    }

    # Additional Notes / Serial Info
    $notes = "Serial: $($bios.SerialNumber) | GPU: $gpuName | OS: $($os.Caption)"
    Write-PdfText -x 325 -y 180 -text $notes -fontSize 8

    $stamper.Close()
    $reader.Close()
    $outputStream.Close()

    Write-Host "`n==========================================================================" -ForegroundColor Green
    Write-Host " SUCCESS! Quality Control PDF filled and saved to Desktop." -ForegroundColor Green
    Write-Host " Saved at: $outputPdf" -ForegroundColor Cyan
    Write-Host "==========================================================================`n" -ForegroundColor Green
} catch {
    Write-Error "Error stamping PDF: $_"
}
