# Windows Service Deployment (NSSM)

This is the Windows equivalent of a systemd `.service` file + `systemctl`,
combined into one PowerShell script: `medinfras.ps1`, backed by
[NSSM](https://nssm.cc/) (the thing that actually registers a plain Node
process as a proper Windows service — auto-start on boot, auto-restart on
crash, managed stdout/stderr logging).

```
deploy/windows/
  config.ps1       <- declarative service definitions (edit this for paths/ports/names)
  medinfras.ps1    <- the control script (install/uninstall/start/stop/restart/status/logs/run)
  tools/           <- put nssm.exe here (or let the script download it)
  README.md        <- this file
```

**Heads up:** this was written and syntax-reviewed carefully, but it could
only be checked from a Linux sandbox with no Windows machine to actually
run it against — there's no substitute for testing it on your server. Run
`-Action Status` first (see below); it's read-only and needs no admin
rights, so it's a safe first check that the script at least loads and
`config.ps1` resolves your paths correctly.

---

## 1. One-time setup

On the Windows Server:

1. Install [Node.js](https://nodejs.org/) (LTS) and make sure `node` is on
   `PATH` (`node --version` in a fresh PowerShell window).
2. Clone/copy this repo, then:
   ```powershell
   npm install
   npm run build            # produces dist/server.js and dist/mcp-server.js
   copy .env.example .env
   notepad .env              # set DOTNET_DLL_PATH, DOTNET_RUNTIME
   ```
3. Get NSSM — either:
   - Run the install step with `-AutoDownloadNssm` (downloads and unpacks
     it into `deploy/windows/tools/nssm.exe` automatically), **or**
   - Download manually from https://nssm.cc/download and place `nssm.exe`
     at `deploy/windows/tools/nssm.exe` (or anywhere on `PATH`).

---

## 2. Install & start the services

From an **elevated** PowerShell (Run as Administrator), in
`deploy/windows/`:

```powershell
.\medinfras.ps1 -Action Install -AutoDownloadNssm
.\medinfras.ps1 -Action Start
.\medinfras.ps1 -Action Status
```

`-Action Install` with no `-Service` installs **both** `MedinfrasAPI` and
`MedinfrasMCP`. Target just one with `-Service Api` or `-Service Mcp`.

Once installed, they also show up in `services.msc` like any other Windows
service, and will auto-start on server reboot.

---

## 3. Day-to-day commands

```powershell
# Status of both services + whether their ports are actually listening
.\medinfras.ps1 -Action Status

# Restart just the API (e.g. after deploying a new build)
.\medinfras.ps1 -Action Restart -Service Api

# Stop everything
.\medinfras.ps1 -Action Stop

# Tail the last 100 lines and keep following (like `tail -f`)
.\medinfras.ps1 -Action Logs -Service Api -Tail 100 -Follow

# Search logs by time range (local time; converts from the UTC timestamps
# the app writes automatically)
.\medinfras.ps1 -Action Logs -Service Api -From "2026-09-07 09:00" -To "2026-09-07 10:00"

# Include stderr too
.\medinfras.ps1 -Action Logs -Service Mcp -Stream both -Tail 200

# Run one service directly in the console (NOT as a service) - useful for
# debugging startup issues without digging through log files
.\medinfras.ps1 -Action Run -Service Api

# Remove the services entirely
.\medinfras.ps1 -Action Uninstall
```

All actions except `Status`, `Logs`, and `Run` require an elevated
PowerShell session — the script checks this itself and tells you if you're
not elevated, rather than failing with a cryptic Windows error.

---

## 4. Deploying a new build

```powershell
git pull
npm install
npm run build
cd deploy\windows
.\medinfras.ps1 -Action Restart
```

NSSM points at the compiled `dist\*.js` files (see `config.ps1`), so a
restart after `npm run build` is all a normal deploy needs — no
reinstall required unless you change the Node path, script path, or port
in `config.ps1`.

---

## 5. Logs and how time-search works

Every log line the app writes starts with an ISO-8601 UTC timestamp:

```
[2026-09-07T09:15:03.123Z] [INFO] Medinfras API listening on http://localhost:3000
```

(`src/core/logger.ts` is what produces this format — use it instead of
raw `console.log`/`console.error` anywhere in the app, or log-search stops
working for those lines.)

`-Action Logs -From ... -To ...` parses that timestamp out of each line,
converts it to your local time, and filters by it — so you can jump
straight to "what happened between 9 and 10am" instead of scrolling.

NSSM also rotates these logs on its own (configured at install time in
`medinfras.ps1`): daily, or past 10MB, whichever comes first. Rotated
files pick up a numeric suffix; `-Action Logs` only reads the current
(non-rotated) file — `Get-Content` the rotated ones directly if you need
older history.

---

## 6. Notes for further development

- **Reverse proxy / HTTPS.** NSSM just keeps the Node process alive; it
  doesn't terminate TLS or give you a nice hostname. Put IIS (with
  Application Request Routing) or another reverse proxy in front of ports
  3000/3100 for that.
- **Firewall.** If clients connect from other machines, open the ports:
  `New-NetFirewallRule -DisplayName "Medinfras API" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow`
  (and 3100 for MCP, if needed externally).
- **Health checks.** `Status` only checks "is the port listening", not
  "is `/medinfras/api/health` returning 200". Wire up a real HTTP health
  check (e.g. via a scheduled task calling `Invoke-WebRequest`) if you want
  alerting beyond process-is-alive.
- **Config changes.** Adding a third service later (e.g. if you split MCP
  tools into their own process per domain) is one new entry in
  `config.ps1`'s `$Services` array — `medinfras.ps1` needs no changes.
