<#
.SYNOPSIS
    Manage the Medinfras Windows services (REST API + MCP/SSE) via NSSM.
    This is the Windows equivalent of your systemd .service + systemctl setup.

.PARAMETER Action
    Install    - register the service(s) with NSSM (build first: npm run build)
    Uninstall  - stop and remove the service(s)
    Start      - start the service(s)
    Stop       - stop the service(s)
    Restart    - restart the service(s)
    Status     - show Windows service status + whether the port is listening
    Logs       - tail or time-range-search the service's log files
    Run        - run one service directly in the console (not as a service) for debugging

.PARAMETER Service
    Which service to target: Api, Mcp, or All (default: All). Run requires Api or Mcp.

.PARAMETER Tail
    Logs: number of lines to show from the end (default 50). Ignored with -From/-To.

.PARAMETER Follow
    Logs: keep streaming new lines (like `tail -f`). Ignored with -From/-To.

.PARAMETER Stream
    Logs: stdout, stderr, or both (default stdout).

.PARAMETER From / -To
    Logs: search window, e.g. -From "2026-09-07 09:00" -To "2026-09-07 10:00"
    (local time - converted from the UTC timestamps in the log automatically).

.PARAMETER Force
    Install: if the service already exists, remove and reinstall it.

.PARAMETER AutoDownloadNssm
    Install/Uninstall: download nssm.exe automatically if it isn't found.

.EXAMPLE
    .\medinfras.ps1 -Action Install -AutoDownloadNssm
    .\medinfras.ps1 -Action Status
    .\medinfras.ps1 -Action Logs -Service Api -Tail 100 -Follow
    .\medinfras.ps1 -Action Logs -Service Api -From "2026-09-07 09:00" -To "2026-09-07 10:00"
    .\medinfras.ps1 -Action Restart -Service Mcp
    .\medinfras.ps1 -Action Run -Service Api
    .\medinfras.ps1 -Action Uninstall
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Uninstall', 'Start', 'Stop', 'Restart', 'Status', 'Logs', 'Run')]
    [string]$Action,

    [ValidateSet('Api', 'Mcp', 'All')]
    [string]$Service = 'All',

    [int]$Tail = 50,
    [switch]$Follow,
    [ValidateSet('stdout', 'stderr', 'both')]
    [string]$Stream = 'stdout',
    [Nullable[datetime]]$From = $null,
    [Nullable[datetime]]$To = $null,

    [switch]$Force,
    [switch]$AutoDownloadNssm
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'config.ps1')

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Assert-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This action requires an elevated PowerShell session. Right-click PowerShell -> 'Run as Administrator' and try again."
        exit 1
    }
}

function Resolve-Nssm {
    if (Test-Path $NssmPath) { return $NssmPath }

    $inPath = Get-Command nssm.exe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }

    if ($AutoDownloadNssm) {
        Write-Host 'nssm.exe not found locally - downloading...' -ForegroundColor Yellow
        $toolsDir = Split-Path $NssmPath -Parent
        New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
        $zipPath = Join-Path $toolsDir 'nssm.zip'

        Invoke-WebRequest -Uri 'https://nssm.cc/release/nssm-2.24.zip' -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $toolsDir -Force
        $arch = if ([Environment]::Is64BitOperatingSystem) { 'win64' } else { 'win32' }
        $extracted = Join-Path $toolsDir "nssm-2.24\$arch\nssm.exe"

        if (Test-Path $extracted) {
            Copy-Item $extracted $NssmPath -Force
        }
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        if (Test-Path $NssmPath) { return $NssmPath }
        Write-Error "Auto-download finished but nssm.exe wasn't found where expected ($extracted). Download it manually - see deploy/windows/README.md."
        exit 1
    }

    Write-Error @"
nssm.exe was not found. Options:
  1) Re-run this command with -AutoDownloadNssm
  2) Download manually from https://nssm.cc/download and place nssm.exe at:
       $NssmPath
  3) Or make sure nssm.exe is on your PATH
"@
    exit 1
}

function Get-TargetServices {
    switch ($Service) {
        'Api' { return @($Services | Where-Object { $_.Name -eq 'MedinfrasAPI' }) }
        'Mcp' { return @($Services | Where-Object { $_.Name -eq 'MedinfrasMCP' }) }
        default { return $Services }
    }
}

function Install-OneService {
    param($Svc, $Nssm)

    $nodeCmd = Get-Command $NodeExe -ErrorAction SilentlyContinue
    if (-not $nodeCmd) {
        Write-Error "node.exe was not found on PATH. Install Node.js, or set `$NodeExe in config.ps1 to its full path."
        exit 1
    }
    $nodePath = $nodeCmd.Source

    $scriptFullPath = Join-Path $ProjectRoot $Svc.ScriptPath
    if (-not (Test-Path $scriptFullPath)) {
        Write-Error "Build output not found: $scriptFullPath`nRun 'npm run build' in $ProjectRoot first."
        exit 1
    }

    $existing = Get-Service -Name $Svc.Name -ErrorAction SilentlyContinue
    if ($existing -and -not $Force) {
        Write-Host "Service '$($Svc.Name)' already exists. Use -Force to remove and reinstall it." -ForegroundColor Yellow
        return
    }
    if ($existing -and $Force) {
        Uninstall-OneService -Svc $Svc -Nssm $Nssm
    }

    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    $stdout = Join-Path $LogDir "$($Svc.Name).out.log"
    $stderr = Join-Path $LogDir "$($Svc.Name).err.log"

    & $Nssm install $Svc.Name $nodePath $scriptFullPath
    & $Nssm set $Svc.Name AppDirectory $ProjectRoot
    & $Nssm set $Svc.Name DisplayName $Svc.DisplayName
    & $Nssm set $Svc.Name Description $Svc.Description
    & $Nssm set $Svc.Name Start SERVICE_AUTO_START
    & $Nssm set $Svc.Name AppStdout $stdout
    & $Nssm set $Svc.Name AppStderr $stderr
    # Log rotation: rotate daily or past 10MB, whichever comes first.
    & $Nssm set $Svc.Name AppRotateFiles 1
    & $Nssm set $Svc.Name AppRotateOnline 1
    & $Nssm set $Svc.Name AppRotateSeconds 86400
    & $Nssm set $Svc.Name AppRotateBytes 10485760
    & $Nssm set $Svc.Name AppEnvironmentExtra 'NODE_ENV=production'
    # If the process dies, restart it after 3s, indefinitely.
    & $Nssm set $Svc.Name AppExit Default Restart
    & $Nssm set $Svc.Name AppRestartDelay 3000

    Write-Host "Installed '$($Svc.Name)'. Start it with: .\medinfras.ps1 -Action Start -Service $Service" -ForegroundColor Green
}

function Uninstall-OneService {
    param($Svc, $Nssm)

    $existing = Get-Service -Name $Svc.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "'$($Svc.Name)' is not installed." -ForegroundColor DarkGray
        return
    }
    if ($existing.Status -ne 'Stopped') {
        Stop-Service -Name $Svc.Name -Force
    }
    & $Nssm remove $Svc.Name confirm
    Write-Host "Removed '$($Svc.Name)'." -ForegroundColor Green
}

function Show-Status {
    param($Svc)

    $existing = Get-Service -Name $Svc.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "$($Svc.Name): NOT INSTALLED" -ForegroundColor DarkGray
        return
    }

    $color = switch ($existing.Status) {
        'Running' { 'Green' }
        'Stopped' { 'Red' }
        default   { 'Yellow' }
    }
    Write-Host "$($Svc.Name): $($existing.Status)" -ForegroundColor $color

    if ($Svc.Port) {
        try {
            $listening = Get-NetTCPConnection -LocalPort $Svc.Port -State Listen -ErrorAction SilentlyContinue
            if ($listening) {
                Write-Host "  Port $($Svc.Port): LISTENING" -ForegroundColor Green
            } else {
                Write-Host "  Port $($Svc.Port): NOT LISTENING" -ForegroundColor Red
            }
        } catch {
            Write-Host "  Port check skipped (Get-NetTCPConnection unavailable on this system)." -ForegroundColor DarkGray
        }
    }

    $stderr = Join-Path $LogDir "$($Svc.Name).err.log"
    if (Test-Path $stderr) {
        $lastError = Get-Content $stderr -Tail 1 -ErrorAction SilentlyContinue
        if ($lastError) {
            Write-Host "  Last error log line: $lastError" -ForegroundColor DarkYellow
        }
    }
}

function Get-LogFiles {
    param($Svc)

    $files = @()
    if ($Stream -in @('stdout', 'both')) { $files += Join-Path $LogDir "$($Svc.Name).out.log" }
    if ($Stream -in @('stderr', 'both')) { $files += Join-Path $LogDir "$($Svc.Name).err.log" }
    return $files
}

function Show-Logs {
    param($Svc)

    foreach ($logFile in (Get-LogFiles -Svc $Svc)) {
        if (-not (Test-Path $logFile)) {
            Write-Host "No log file yet at $logFile" -ForegroundColor DarkGray
            continue
        }

        Write-Host "--- $logFile ---" -ForegroundColor Cyan

        if ($From -or $To) {
            # App log lines look like: [2026-09-07T09:15:03.123Z] [INFO] message
            $pattern = '^\[(?<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)\]'
            Get-Content $logFile | ForEach-Object {
                if ($_ -match $pattern) {
                    $ts = [datetime]::Parse($Matches['ts'], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal).ToLocalTime()
                    $afterFrom = (-not $From) -or ($ts -ge $From)
                    $beforeTo  = (-not $To) -or ($ts -le $To)
                    if ($afterFrom -and $beforeTo) { $_ }
                }
            }
        }
        elseif ($Follow) {
            Get-Content $logFile -Tail $Tail -Wait
        }
        else {
            Get-Content $logFile -Tail $Tail
        }
    }
}

function Invoke-RunForeground {
    param($Svc)

    $scriptFullPath = Join-Path $ProjectRoot $Svc.ScriptPath
    if (-not (Test-Path $scriptFullPath)) {
        Write-Error "Build output not found: $scriptFullPath`nRun 'npm run build' first (or use 'npm run dev' / 'npm run mcp:dev' directly for TypeScript dev mode)."
        exit 1
    }

    Write-Host "Running $($Svc.Name) in the foreground - Ctrl+C to stop." -ForegroundColor Cyan
    Push-Location $ProjectRoot
    try {
        & $NodeExe $scriptFullPath
    } finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$targets = Get-TargetServices

switch ($Action) {
    'Install' {
        Assert-Admin
        $nssm = Resolve-Nssm
        foreach ($svc in $targets) { Install-OneService -Svc $svc -Nssm $nssm }
    }
    'Uninstall' {
        Assert-Admin
        $nssm = Resolve-Nssm
        foreach ($svc in $targets) { Uninstall-OneService -Svc $svc -Nssm $nssm }
    }
    'Start' {
        Assert-Admin
        foreach ($svc in $targets) {
            Start-Service -Name $svc.Name
            Write-Host "Started $($svc.Name)" -ForegroundColor Green
        }
    }
    'Stop' {
        Assert-Admin
        foreach ($svc in $targets) {
            Stop-Service -Name $svc.Name -Force
            Write-Host "Stopped $($svc.Name)" -ForegroundColor Green
        }
    }
    'Restart' {
        Assert-Admin
        foreach ($svc in $targets) {
            Restart-Service -Name $svc.Name -Force
            Write-Host "Restarted $($svc.Name)" -ForegroundColor Green
        }
    }
    'Status' {
        foreach ($svc in $targets) { Show-Status -Svc $svc }
    }
    'Logs' {
        foreach ($svc in $targets) { Show-Logs -Svc $svc }
    }
    'Run' {
        if ($targets.Count -ne 1) {
            Write-Error 'Run requires exactly one target: -Service Api or -Service Mcp.'
            exit 1
        }
        Invoke-RunForeground -Svc $targets[0]
    }
}
