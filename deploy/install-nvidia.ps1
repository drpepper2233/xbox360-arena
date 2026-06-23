[CmdletBinding()]
param(
    # Optional explicit driver URL. If omitted, the current Game Ready driver for the RTX 3090 Ti
    # (Windows 11, DCH) is resolved from NVIDIA's lookup service.
    [string]$DriverUrl,
    [string]$WorkDir = "C:\X360Arena\nvidia"
)

$ErrorActionPreference = "Stop"

# Self-elevate (auto-login shell is non-elevated; the installer needs admin).
$__principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $__principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $__args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    if ($DriverUrl) { $__args += @("-DriverUrl", $DriverUrl) }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $__args
    return
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

if (-not $DriverUrl) {
    Write-Host "[nvidia] resolving latest RTX 3090 Ti / Win11 driver URL..."
    # psid=120 (GeForce RTX 30 Series), pfid=929 (RTX 3090 Ti), osID=135 (Windows 11 64-bit), DCH.
    $lookup = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=120&pfid=929&osID=135&languageCode=1033&isWHQL=1&dch=1&sort1=0&numberOfResults=1"
    $resp = Invoke-RestMethod -Uri $lookup -UseBasicParsing
    $DriverUrl = $resp.IDS[0].downloadInfo.DownloadURL
    Write-Host "[nvidia] version $($resp.IDS[0].downloadInfo.Version) -> $DriverUrl"
}

$exe = Join-Path $WorkDir "nvidia-driver.exe"
Write-Host "[nvidia] downloading driver (~900 MB)..."
Invoke-WebRequest -Uri $DriverUrl -OutFile $exe -UseBasicParsing

# Silent install. Use ONLY '-s -noreboot'. The '-clean'/'-nofinish' combo made the outer
# self-extractor bail in seconds without installing; '-s -noreboot' unpacks (CPU-bound, slow on
# weak hosts) and installs cleanly with no reboot. nvidia-smi.exe appearing == success.
Write-Host "[nvidia] installing silently (this is CPU-bound; allow several minutes)..."
$p = Start-Process -FilePath $exe -ArgumentList "-s", "-noreboot" -PassThru
$p.WaitForExit()

$smi = "C:\Windows\System32\nvidia-smi.exe"
$deadline = (Get-Date).AddMinutes(8)
while (-not (Test-Path $smi) -and (Get-Date) -lt $deadline) { Start-Sleep 10 }

if (Test-Path $smi) {
    Write-Host "[nvidia] driver installed:"
    & $smi
    # Enable NVENC capture: disable the emulated VGA so Sunshine captures the NVIDIA display.
    Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match "Basic Display" } |
        Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue
    Restart-Service SunshineService -Force -ErrorAction SilentlyContinue
    Write-Host "[nvidia] DONE. Emulated VGA disabled, Sunshine restarted for hardware NVENC."
} else {
    throw "[nvidia] nvidia-smi.exe not found after install — driver install failed."
}
