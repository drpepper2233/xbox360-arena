#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$InstallRoot = "C:\X360Arena",
    [string]$PayloadRoot = "C:\X360Arena\deploy",
    [switch]$SkipGuestSetup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "bootstrap.ps1 must run from an elevated administrator session."
    }
}

function Write-Step {
    param([Parameter(Mandatory=$true)][string]$Message)
    Write-Host "[bootstrap] $Message"
}

function Get-PayloadCandidate {
    $roots = @(Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root)
    foreach ($root in $roots) {
        foreach ($relative in @("deploy", "X360Arena\deploy")) {
            $candidate = Join-Path $root $relative
            if (Test-Path -LiteralPath (Join-Path $candidate "guest-setup.ps1")) {
                return $candidate
            }
        }
    }
    return $null
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    New-Directory -Path $Destination
    Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
}

function Stage-Payload {
    New-Directory -Path $InstallRoot
    New-Directory -Path $PayloadRoot

    if (Test-Path -LiteralPath (Join-Path $PayloadRoot "guest-setup.ps1")) {
        Write-Step "deploy payload already present at $PayloadRoot"
        return
    }

    $candidate = Get-PayloadCandidate
    if (-not $candidate) {
        throw "guest-setup.ps1 not found in $PayloadRoot or mounted deploy payload."
    }

    Write-Step "copying deploy payload from $candidate to $PayloadRoot"
    Copy-DirectoryContents -Source $candidate -Destination $PayloadRoot

    $candidateRepoRoot = Split-Path -Parent $candidate
    $sourceConfig = Join-Path $candidateRepoRoot "config"
    if (Test-Path -LiteralPath $sourceConfig) {
        $targetConfig = Join-Path $InstallRoot "config"
        Write-Step "copying config payload from $sourceConfig to $targetConfig"
        Copy-DirectoryContents -Source $sourceConfig -Destination $targetConfig
    }
}

function Enable-PrivateNetworkProfile {
    Write-Step "setting active network profiles to Private"
    try {
        Get-NetConnectionProfile |
            Where-Object { $_.IPv4Connectivity -ne "Disconnected" -or $_.IPv6Connectivity -ne "Disconnected" } |
            Set-NetConnectionProfile -NetworkCategory Private
    } catch {
        Write-Warning "Could not set all network profiles to Private: $($_.Exception.Message)"
    }
}

function Enable-Rdp {
    Write-Step "enabling Remote Desktop"
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1
    Set-Service -Name TermService -StartupType Automatic
    Start-Service -Name TermService -ErrorAction SilentlyContinue

    try {
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    } catch {
        if (-not (Get-NetFirewallRule -DisplayName "X360 Arena RDP TCP 3389" -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName "X360 Arena RDP TCP 3389" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 | Out-Null
        }
    }

    & net.exe localgroup "Remote Desktop Users" "arena" /add 2>$null | Out-Null
}

function Ensure-OpenSshServer {
    Write-Step "installing and enabling OpenSSH Server"
    $capabilityName = "OpenSSH.Server~~~~0.0.1.0"
    $capability = Get-WindowsCapability -Online -Name $capabilityName -ErrorAction SilentlyContinue
    if (-not $capability -or $capability.State -ne "Installed") {
        Add-WindowsCapability -Online -Name $capabilityName | Out-Null
    }

    $service = Get-Service -Name sshd -ErrorAction Stop
    Set-Service -Name $service.Name -StartupType Automatic
    if ($service.Status -ne "Running") {
        Start-Service -Name $service.Name
    }

    if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" `
            -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 22 | Out-Null
    } else {
        Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Enabled True -Direction Inbound -Action Allow
    }
}

function Set-OpenSshDefaultShell {
    Write-Step "setting OpenSSH default shell to Windows PowerShell"
    $openSshKey = "HKLM:\SOFTWARE\OpenSSH"
    New-Item -Path $openSshKey -Force | Out-Null
    New-ItemProperty -Path $openSshKey `
        -Name "DefaultShell" `
        -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -PropertyType String `
        -Force | Out-Null
}

function Invoke-GuestSetup {
    if ($SkipGuestSetup) {
        Write-Step "skipping guest-setup.ps1 by request"
        return
    }

    $guestSetup = Join-Path $PayloadRoot "guest-setup.ps1"
    if (-not (Test-Path -LiteralPath $guestSetup)) {
        throw "Missing guest setup script: $guestSetup"
    }

    Write-Step "running $guestSetup"
    & $guestSetup -InstallRoot $InstallRoot
}

Assert-Administrator
New-Directory -Path $InstallRoot
New-Directory -Path (Join-Path $InstallRoot "logs")
$logPath = Join-Path $InstallRoot "logs\bootstrap.log"

Start-Transcript -Path $logPath -Append | Out-Null
try {
    Stage-Payload
    Enable-PrivateNetworkProfile
    Enable-Rdp
    Ensure-OpenSshServer
    Set-OpenSshDefaultShell
    Invoke-GuestSetup

    Set-Content -LiteralPath (Join-Path $InstallRoot ".bootstrap-complete") `
        -Value ("completed {0:o}" -f (Get-Date)) `
        -Encoding ASCII
    Write-Step "complete"
} finally {
    Stop-Transcript | Out-Null
}
