<#
  config.ps1

  Declarative definition of every Windows service this app runs — this is
  the equivalent of your systemd .service files. Edit THIS file (not
  medinfras.ps1) when a script path, port, or service name changes.
#>

# Root of the repo (this file lives in <repo>\deploy\windows\config.ps1).
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# One entry per Windows service. ScriptPath is relative to $ProjectRoot and
# must point at the COMPILED .js file (run `npm run build` first).
$Services = @(
    @{
        Name        = 'MedinfrasAPI'
        DisplayName = 'Medinfras REST API'
        Description = 'Medinfras .NET business-layer REST gateway (Express)'
        ScriptPath  = 'dist\server.js'
        Port        = 3000
    },
    @{
        Name        = 'MedinfrasMCP'
        DisplayName = 'Medinfras MCP (SSE) Server'
        Description = 'Medinfras MCP tools server over Server-Sent Events'
        ScriptPath  = 'dist\mcp-server.js'
        Port        = 3100
    }
)

# Where NSSM lives. If it's not here and not on PATH, medinfras.ps1 will
# tell you how to get it (see deploy/windows/README.md).
$NssmPath = Join-Path $PSScriptRoot 'tools\nssm.exe'

# Where service stdout/stderr logs are written. NSSM handles rotation
# (configured per-service at install time in medinfras.ps1).
$LogDir = Join-Path $ProjectRoot 'logs'

# node.exe - resolved from PATH by default. Override with a full path if
# this machine has multiple Node installs and you need a specific one.
$NodeExe = 'node.exe'
