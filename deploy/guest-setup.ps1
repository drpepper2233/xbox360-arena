#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$InstallRoot = "C:\X360Arena",
    [string]$GamesConfigDir,
    [switch]$ForceDownload
)

# Set-StrictMode removed: it turned benign missing-property reads into hard crashes
$ErrorActionPreference = "Stop"
# Windows default execution policy is Restricted and blocks this script; force Bypass (we are elevated).
try { Set-ExecutionPolicy Bypass -Scope LocalMachine -Force -ErrorAction SilentlyContinue } catch {}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "..")).Path
if (-not $GamesConfigDir) {
    $GamesConfigDir = Join-Path $RepoRoot "config\games"
}

$PackageDir = Join-Path $InstallRoot "packages"
$XeniaDir = Join-Path $InstallRoot "XeniaCanary"
$XeniaManagerDir = Join-Path $InstallRoot "XeniaManager"
$MoonlightWebDir = Join-Path $InstallRoot "MoonlightWeb"
$XeniaConfigDir = Join-Path $XeniaDir "config"
$SunshineConfigDir = Join-Path ${env:ProgramFiles} "Sunshine\config"

function New-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-PrimaryIPv4 {
    try {
        $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address } |
            Select-Object -First 1
        if ($cfg -and $cfg.IPv4Address) { return $cfg.IPv4Address.IPAddress }
    } catch {}
    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch "^(127\.|169\.254\.)" } |
        Select-Object -First 1 -ExpandProperty IPAddress -ErrorAction SilentlyContinue
    if ($ip) { return $ip }
    return "127.0.0.1"
}

function Get-GitHubAsset {
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)][string]$AssetPattern
    )

    $headers = @{ "User-Agent" = "xbox360-arena-guest-setup" }
    $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repository/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
    if (-not $asset) {
        throw "No release asset matching '$AssetPattern' found in $Repository latest release $($release.tag_name)."
    }

    [pscustomobject]@{
        Repository = $Repository
        Tag = $release.tag_name
        AssetName = $asset.name
        Url = $asset.browser_download_url
        Digest = $asset.digest
    }
}

function Save-Asset {
    param(
        [Parameter(Mandatory=$true)][pscustomobject]$Asset,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    $hasValidExistingFile = $false
    if ((Test-Path -LiteralPath $Destination) -and $Asset.Digest -match "^sha256:(.+)$") {
        $expectedHash = $Matches[1].ToUpperInvariant()
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash.ToUpperInvariant()
        $hasValidExistingFile = ($expectedHash -eq $actualHash)
    }

    if (-not $ForceDownload -and $hasValidExistingFile) {
        return
    }

    New-Directory -Path (Split-Path -Parent $Destination)
    Invoke-WebRequest -UseBasicParsing -Uri $Asset.Url -OutFile $Destination

    if ($Asset.Digest -match "^sha256:(.+)$") {
        $expectedHash = $Matches[1].ToUpperInvariant()
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash.ToUpperInvariant()
        if ($expectedHash -ne $actualHash) {
            throw "Hash mismatch for $($Asset.AssetName): expected $expectedHash, got $actualHash."
        }
    }
}

function Install-ZipAsset {
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)][string]$AssetPattern,
        [Parameter(Mandatory=$true)][string]$TargetDir,
        [Parameter(Mandatory=$true)][string]$ExeNamePattern
    )

    $asset = Get-GitHubAsset -Repository $Repository -AssetPattern $AssetPattern
    $zipPath = Join-Path $PackageDir $asset.AssetName
    $tagPath = Join-Path $TargetDir ".release-tag"
    $existingExe = if (Test-Path -LiteralPath $TargetDir) {
        Get-ChildItem -LiteralPath $TargetDir -Recurse -File -Filter "*.exe" |
            Where-Object { $_.Name -like $ExeNamePattern } |
            Select-Object -First 1
    }

    if (-not $ForceDownload -and $existingExe -and (Test-Path -LiteralPath $tagPath)) {
        $installedTag = (Get-Content -LiteralPath $tagPath -Raw).Trim()
        if ($installedTag -eq $asset.Tag) {
            return $existingExe.FullName
        }
    }

    Save-Asset -Asset $asset -Destination $zipPath
    if (Test-Path -LiteralPath $TargetDir) {
        Remove-Item -LiteralPath $TargetDir -Recurse -Force
    }
    New-Directory -Path $TargetDir
    Expand-Archive -LiteralPath $zipPath -DestinationPath $TargetDir -Force
    Set-Content -LiteralPath $tagPath -Value $asset.Tag -Encoding UTF8

    $exe = Get-ChildItem -LiteralPath $TargetDir -Recurse -File -Filter "*.exe" |
        Where-Object { $_.Name -like $ExeNamePattern } |
        Select-Object -First 1
    if (-not $exe) {
        throw "Installed $($asset.AssetName), but no executable matching '$ExeNamePattern' was found under $TargetDir."
    }

    return $exe.FullName
}

function Install-Sunshine {
    $sunshineExe = Join-Path ${env:ProgramFiles} "Sunshine\sunshine.exe"
    $asset = Get-GitHubAsset -Repository "LizardByte/Sunshine" -AssetPattern "Sunshine-Windows-AMD64-installer\.msi$"
    $msiPath = Join-Path $PackageDir $asset.AssetName
    Save-Asset -Asset $asset -Destination $msiPath

    if ($ForceDownload -or -not (Test-Path -LiteralPath $sunshineExe)) {
        $arguments = "/i `"$msiPath`" /qn /norestart"
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "Sunshine MSI failed with exit code $($process.ExitCode)."
        }
    }

    $service = Get-Service |
        Where-Object { $_.Name -like "*sunshine*" -or $_.DisplayName -like "*Sunshine*" } |
        Select-Object -First 1
    if ($service) {
        Set-Service -Name $service.Name -StartupType Automatic
        if ($service.Status -ne "Running") {
            Start-Service -Name $service.Name
        }
    } else {
        Write-Warning "Sunshine installed, but no Sunshine service was found. Open Sunshine once or run its service installer before final verification."
    }
}

function Set-KeyValueFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][hashtable]$Pairs
    )

    $content = @()
    if (Test-Path -LiteralPath $Path) {
        $content = @(Get-Content -LiteralPath $Path)
    }

    foreach ($key in $Pairs.Keys) {
        $line = "$key = $($Pairs[$key])"
        $pattern = "^\s*$([regex]::Escape($key))\s*="
        $found = $false
        for ($i = 0; $i -lt $content.Count; $i++) {
            if ($content[$i] -match $pattern) {
                $content[$i] = $line
                $found = $true
            }
        }
        if (-not $found) {
            $content += $line
        }
    }

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Configure-Xenia {
    param([Parameter(Mandatory=$true)][string]$XeniaExe)

    New-Directory -Path $XeniaConfigDir
    Set-Content -LiteralPath (Join-Path $XeniaDir "portable.txt") -Value "portable config for xbox360-arena" -Encoding ASCII

    $baseConfig = Join-Path $XeniaDir "xenia-canary.config.toml"
    Set-KeyValueFile -Path $baseConfig -Pairs @{
        "gpu" = '"d3d12"'
        "apu" = '"sdl"'
        "license_mask" = "0"
        "apply_patches" = "true"
        "max_queued_frames" = "3"
        "mount_cache" = "true"
    }

    if (-not (Test-Path -LiteralPath $GamesConfigDir)) {
        Write-Warning "No config/games directory found at $GamesConfigDir. Per-game configs will be applied when that layer lands."
        return
    }

    $gameConfigs = @(Get-ChildItem -LiteralPath $GamesConfigDir -Filter "*.toml" -File)
    foreach ($gameConfig in $gameConfigs) {
        $raw = Get-Content -LiteralPath $gameConfig.FullName -Raw
        if ($raw -notmatch "(?m)^\s*title_id\s*=\s*[""']?([0-9A-Fa-f]{8})[""']?") {
            throw "$($gameConfig.FullName) is missing title_id = `"584111F7`" style metadata."
        }

        $titleId = $Matches[1].ToUpperInvariant()
        $lines = @(Get-Content -LiteralPath $gameConfig.FullName)
        $hasXeniaSection = [bool]($lines | Where-Object { $_ -match "^\s*\[xenia\]\s*$" } | Select-Object -First 1)
        $output = @()

        if ($hasXeniaSection) {
            $insideXenia = $false
            foreach ($line in $lines) {
                if ($line -match "^\s*\[xenia\]\s*$") {
                    $insideXenia = $true
                    continue
                }
                if ($line -match "^\s*\[") {
                    $insideXenia = $false
                    continue
                }
                if ($insideXenia) {
                    $output += $line
                }
            }
        } else {
            foreach ($line in $lines) {
                if ($line -match "^\s*(title_id|title|slug|compatibility|tier|notes|rom|rom_hint)\s*=") {
                    continue
                }
                if ($line -match "^\s*\[(game|metadata|meta)\]\s*$") {
                    continue
                }
                $output += $line
            }
        }

        if (-not ($output | Where-Object { $_.Trim().Length -gt 0 -and $_.Trim() -notmatch "^#" })) {
            throw "$($gameConfig.FullName) produced an empty Xenia config for title $titleId."
        }

        $target = Join-Path $XeniaConfigDir "$titleId.config.toml"
        Set-Content -LiteralPath $target -Value $output -Encoding UTF8
    }
}

function Configure-Sunshine {
    param(
        [Parameter(Mandatory=$true)][string]$XeniaExe,
        [Parameter(Mandatory=$true)][string]$XeniaManagerExe
    )

    New-Directory -Path $SunshineConfigDir
    $sunshineConfig = Join-Path $SunshineConfigDir "sunshine.conf"
    Set-KeyValueFile -Path $sunshineConfig -Pairs @{
        "sunshine_name" = '"x360-arena"'
        "min_log_level" = "info"
        "channels" = "1"
        "controller" = "enabled"
        "gamepad" = "x360"
        "keyboard" = "enabled"
        "mouse" = "enabled"
        "origin_web_ui_allowed" = "lan"
        "file_apps" = "apps.json"
        "nvenc_preset" = "1"
    }

    $apps = [ordered]@{
        env = [ordered]@{
            PATH = '$(PATH)'
        }
        apps = @(
            [ordered]@{
                name = "Desktop"
                "image-path" = "desktop.png"
            },
            [ordered]@{
                name = "Xenia Manager"
                detached = @($XeniaManagerExe)
                "image-path" = "desktop.png"
            },
            [ordered]@{
                name = "Xenia Canary"
                cmd = $XeniaExe
                "working-dir" = $XeniaDir
                "image-path" = "desktop.png"
            }
        )
    }
    $apps | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $SunshineConfigDir "apps.json") -Encoding UTF8
}

function Configure-MoonlightWeb {
    param([Parameter(Mandatory=$true)][string]$MoonlightWebExe)

    $moonlightWebRunDir = Split-Path -Parent $MoonlightWebExe
    $serverDir = Join-Path $moonlightWebRunDir "server"
    New-Directory -Path $serverDir
    # CRITICAL: write config.json as clean UTF-8 with NO BOM. The web-server is a Rust binary
    # whose serde JSON parser rejects a BOM ("expected value, line 1 column 1"). PowerShell's
    # Set-Content -Encoding UTF8 emits a BOM, so use .NET WriteAllText with a no-BOM encoder.
    # "{}" = all defaults (binds 0.0.0.0:8080, first_login_create_admin=true) — verified working.
    # A partial web_server object fails ("missing field first_login_create_admin"), so omit it.
    [System.IO.File]::WriteAllText((Join-Path $serverDir "config.json"), "{}", (New-Object System.Text.UTF8Encoding($false)))

    # Run via Scheduled Task: a process spawned over an SSH session is killed when the session
    # closes, so launching web-server.exe directly does not persist. The task survives + auto-starts.
    $taskName = "X360Arena-MoonlightWebStream"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute $MoonlightWebExe -WorkingDirectory $moonlightWebRunDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
}

function Ensure-FirewallRule {
    param(
        [Parameter(Mandatory=$true)][string]$DisplayName,
        [Parameter(Mandatory=$true)][string]$Protocol,
        [Parameter(Mandatory=$true)][string]$LocalPort
    )

    # Remove-and-recreate is simpler/idempotent. Split the port string into an array so mixed
    # range+list values ("47998-48000,48010") are accepted — passing the raw string fails with
    # "The port is invalid." -Profile Any so it works on Public networks (the VM defaults to Public).
    Remove-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $DisplayName -Direction Inbound -Action Allow -Protocol $Protocol -LocalPort ($LocalPort -split ',') -Profile Any | Out-Null
}

function Open-StreamingFirewall {
    Ensure-FirewallRule -DisplayName "X360 Arena Sunshine TCP" -Protocol "TCP" -LocalPort "47984,47989,47990,48010"
    Ensure-FirewallRule -DisplayName "X360 Arena Sunshine UDP" -Protocol "UDP" -LocalPort "47998-48000,48010"
    Ensure-FirewallRule -DisplayName "X360 Arena Moonlight Web TCP" -Protocol "TCP" -LocalPort "8080"
    Ensure-FirewallRule -DisplayName "X360 Arena Moonlight WebRTC UDP" -Protocol "UDP" -LocalPort "40000-40010"
}

function Test-ViGEmBus {
    $vigem = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -like "*ViGEm*" -or $_.FriendlyName -like "*Virtual Gamepad Emulation Bus*" } |
        Select-Object -First 1
    if (-not $vigem) {
        Write-Warning "ViGEmBus was not detected. Install it from Sunshine Web UI > Troubleshooting, then reboot, before accepting gamepad DONE-WHEN."
    }
}

function Enable-NvencCapture {
    # Sunshine only uses NVENC if it captures the NVIDIA display. With both the emulated VGA and
    # the passed-through GPU present, Sunshine captures the emulated VGA (1Hz) and falls back to
    # software libx264. Disable the emulated adapter so Sunshine captures the 3090 Ti -> hevc_nvenc.
    # Guarded: only act once the NVIDIA GPU is present AND healthy (i.e. driver installed), so this
    # is safe to run pre-GPU (it just no-ops and tells you to re-run after the driver lands).
    $nv = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match "NVIDIA" -and $_.Status -eq "OK" }
    if ($nv) {
        Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -match "Basic Display" } |
            Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue
        Restart-Service SunshineService -Force -ErrorAction SilentlyContinue
        Write-Host "NVENC enabled: emulated VGA disabled, Sunshine restarted to capture the NVIDIA GPU."
    } else {
        Write-Host "NVENC pending: NVIDIA GPU not healthy yet. Bind the GPU + install the driver, then re-run this script to switch Sunshine to hardware encoding."
    }
}

New-Directory -Path $InstallRoot
New-Directory -Path $PackageDir

$xeniaExe = Install-ZipAsset -Repository "xenia-canary/xenia-canary" -AssetPattern "xenia_canary_windows\.zip$" -TargetDir $XeniaDir -ExeNamePattern "xenia*.exe"
$xeniaManagerExe = Install-ZipAsset -Repository "xenia-manager/xenia-manager" -AssetPattern "xenia_manager\.zip$" -TargetDir $XeniaManagerDir -ExeNamePattern "*Xenia*Manager*.exe"
$moonlightWebExe = Install-ZipAsset -Repository "MrCreativ3001/moonlight-web-stream" -AssetPattern "moonlight-web-x86_64-pc-windows-gnu\.zip$" -TargetDir $MoonlightWebDir -ExeNamePattern "web-server.exe"

Configure-Xenia -XeniaExe $xeniaExe
Install-Sunshine
Configure-Sunshine -XeniaExe $xeniaExe -XeniaManagerExe $xeniaManagerExe
Configure-MoonlightWeb -MoonlightWebExe $moonlightWebExe
Open-StreamingFirewall
Test-ViGEmBus
Enable-NvencCapture

$streamUrl = "http://$(Get-PrimaryIPv4):8080"
$sunshineUrl = "https://$(Get-PrimaryIPv4):47990"
Write-Host "Chrome stream URL: $streamUrl"
Write-Host "Sunshine pairing/config URL: $sunshineUrl"
Write-Host "Moonlight Web setup: create first admin user, add PC localhost with default Sunshine port, pair PIN in Sunshine, launch Desktop or Xenia Manager."
