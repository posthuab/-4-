#requires -RunAsAdministrator

<#
.SYNOPSIS
    One-click fix for Xbox Live / Forza Horizon 4 online connectivity issues.

.DESCRIPTION
    Repairs the common system-level causes of Xbox Live and Forza Horizon 4
    online-mode failures. All operations are local Windows configuration
    changes; nothing is downloaded, installed, or fetched from the internet.

    Fixes applied:
      1. IPv6 components      - re-enable DisabledComponents + adapter bindings
      2. Teredo tunnel        - set to enterpriseclient mode
      3. Network location     - switch connected profiles to Private
      4. Xbox services        - set to Automatic startup and start them
      5. Time synchronization - configure China NTP servers and force resync
      6. Xbox auth cache      - clear token cache + Xbl credentials (optional)

.PARAMETER ResetAuth
    Also clear the Xbox authentication cache and credentials.
    This forces a fresh sign-in prompt on the next game launch.

.PARAMETER SkipTeredo
    Skip the Teredo / IPv6 repair steps.

.PARAMETER SkipTimeSync
    Skip the time synchronization step.

.EXAMPLE
    .\Fix-XboxLive.ps1

.EXAMPLE
    .\Fix-XboxLive.ps1 -ResetAuth

.NOTES
    Must be run as Administrator. A reboot is recommended afterwards so the
    IPv6 and Teredo changes fully take effect.
#>

[CmdletBinding()]
param(
    [switch]$ResetAuth,
    [switch]$SkipTeredo,
    [switch]$SkipTimeSync
)

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

function Write-StepHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 64) -ForegroundColor Cyan
    Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
    Write-Host ("=" * 64) -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host ("  [OK]   {0}" -f $Text) -ForegroundColor Green
}

function Write-Fail {
    param([string]$Text)
    Write-Host ("  [FAIL] {0}" -f $Text) -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Fix routines
# ---------------------------------------------------------------------------

function Repair-IPv6 {
    Write-StepHeader "1/6  Enable IPv6 components"

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
    Set-ItemProperty -Path $path -Name 'DisabledComponents' -Value 0 -Type DWord -ErrorAction SilentlyContinue

    $value = (Get-ItemProperty -Path $path -Name 'DisabledComponents' -ErrorAction SilentlyContinue).DisabledComponents
    if ($null -eq $value -or $value -eq 0) {
        Write-Ok "DisabledComponents = 0 (all IPv6 components enabled)"
    } else {
        Write-Fail "Failed to update DisabledComponents (current value: $value)"
    }

    Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
        Enable-NetAdapterBinding -Name $_.Name -ComponentID 'ms_tcpip6' -ErrorAction SilentlyContinue
    }
    Write-Ok "IPv6 binding enabled on all adapters"
}

function Repair-Teredo {
    Write-StepHeader "2/6  Configure Teredo tunnel"

    netsh interface teredo set state enterpriseclient | Out-Null
    Write-Ok "Teredo mode set to enterpriseclient"
}

function Repair-NetworkCategory {
    Write-StepHeader "3/6  Set network location to Private"

    $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue |
        Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' }

    if (-not $profiles) {
        Write-Fail "No connected network profile found"
        return
    }

    foreach ($profile in $profiles) {
        Set-NetConnectionProfile -InterfaceAlias $profile.InterfaceAlias -NetworkCategory Private -ErrorAction SilentlyContinue
        Write-Ok ("Network '{0}' -> Private" -f $profile.Name)
    }
}

function Repair-XboxServices {
    Write-StepHeader "4/6  Configure Xbox services"

    $services = @(
        'XblAuthManager',
        'XblGameSave',
        'XboxGipSvc',
        'XboxNetApiSvc',
        'GamingServices',
        'GamingServicesNet',
        'iphlpsvc'
    )

    foreach ($name in $services) {
        Set-Service -Name $name -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name $name -ErrorAction SilentlyContinue

        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -eq 'Running') {
                Write-Ok ("{0,-20} Running (Automatic)" -f $name)
            } else {
                Write-Fail ("{0,-20} {1}" -f $name, $service.Status)
            }
        }
    }
}

function Repair-TimeSync {
    Write-StepHeader "5/6  Configure time synchronization"

    Set-Service -Name 'W32Time' -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name 'W32Time' -ErrorAction SilentlyContinue

    w32tm /config /manualpeerlist:"ntp.aliyun.com,ntp.tencent.com" /syncfromflags:manual /reliable:YES | Out-Null
    w32tm /config /update | Out-Null
    w32tm /resync /force | Out-Null

    $timeService = Get-Service -Name 'W32Time' -ErrorAction SilentlyContinue
    if ($timeService -and $timeService.Status -eq 'Running') {
        Write-Ok "W32Time running (NTP: ntp.aliyun.com, ntp.tencent.com)"
    } else {
        Write-Fail "W32Time service status: $($timeService.Status)"
    }
}

function Reset-XboxAuth {
    Write-StepHeader "6/6  Clear Xbox authentication cache"

    $packages = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter 'Microsoft.XboxIdentityProvider*' -ErrorAction SilentlyContinue
    foreach ($package in $packages) {
        $tokenBroker = Join-Path $package.FullName 'AC\TokenBroker'
        if (Test-Path $tokenBroker) {
            Remove-Item (Join-Path $tokenBroker 'Accounts') -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item (Join-Path $tokenBroker 'Cache') -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok ("Cleared token cache: {0}" -f $package.Name)
        }
    }

    $removed = 0
    $credentials = cmdkey /list 2>&1 | Out-String
    foreach ($line in ($credentials -split "`r`n")) {
        if ($line -match 'Xbl') {
            $target = ($line -replace '^.*?:\s*', '').Trim()
            if ($target) {
                cmdkey /delete:"$target" 2>&1 | Out-Null
                $removed++
            }
        }
    }
    Write-Ok "Removed $removed Xbl credential(s)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "  Xbox Live / Forza Horizon 4 Online Fix" -ForegroundColor Yellow
Write-Host "  System-level repair, no downloads required" -ForegroundColor DarkGray
Write-Host ""

if (-not $SkipTeredo) {
    Repair-IPv6
    Repair-Teredo
}

Repair-NetworkCategory
Repair-XboxServices

if (-not $SkipTimeSync) {
    Repair-TimeSync
}

if ($ResetAuth) {
    Reset-XboxAuth
}

Write-StepHeader "Summary"

Write-Host ""
Write-Host "  Teredo state:" -ForegroundColor Gray
netsh interface teredo show state

Write-Host ""
Write-Host "  Xbox services:" -ForegroundColor Gray
Get-Service XblAuthManager,XblGameSave,XboxGipSvc,XboxNetApiSvc -ErrorAction SilentlyContinue |
    Select-Object Name,Status,StartType |
    Format-Table -AutoSize

Write-Host ""
Write-Host "  Done. Restart your computer for the changes to fully apply." -ForegroundColor Yellow
if ($ResetAuth) {
    Write-Host "  The next game launch will prompt you to sign in again." -ForegroundColor Yellow
}
Write-Host ""
