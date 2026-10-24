<#
.SYNOPSIS
  Common IIS setup for all 4 office apps, driven by config.yaml.
  Creates (if missing) each app's IIS Application Pool, IIS Site, and
  wires the site up to run that app's Python code via FastCGI.

.USAGE
  Run from an elevated PowerShell prompt:
    .\setup_iis.ps1                          # all projects
    .\setup_iis.ps1 -ProjectName ticket_tracker   # just one

.NOTES
  Idempotent: safe to re-run. Skips anything that already exists rather
  than recreating it, so re-running after a code update does not reset
  IIS settings.
#>

param(
    [string]$ProjectName = ""
)

Import-Module WebAdministration

$ConfigPath = Join-Path $PSScriptRoot "config.yaml"

function Get-YamlConfig {
    # Minimal YAML reader for this one config file's shape -- avoids a
    # third-party PowerShell YAML module dependency. Uses Python (already
    # required for the app itself) to convert to JSON, which PowerShell
    # parses natively.
    $json = python -c "import yaml, json, sys; print(json.dumps(yaml.safe_load(open(sys.argv[1], encoding='utf-8'))))" $ConfigPath
    return $json | ConvertFrom-Json
}

function Set-IisAppPool {
    param($Pool, $ServiceAccount)

    $poolPath = "IIS:\AppPools\$Pool"
    if (-not (Test-Path $poolPath)) {
        New-WebAppPool -Name $Pool | Out-Null
        Write-Host "  [OK] app pool '$Pool' created"
    } else {
        Write-Host "  [OK] app pool '$Pool' already exists"
    }

    Set-ItemProperty $poolPath -Name "managedRuntimeVersion" -Value ""  # no .NET CLR, Python runs via FastCGI

    if ($ServiceAccount) {
        Set-ItemProperty $poolPath -Name "processModel.identityType" -Value "SpecificUser"
        Set-ItemProperty $poolPath -Name "processModel.userName" -Value $ServiceAccount
        Write-Host "  [OK] app pool identity set to $ServiceAccount (password must be set separately via IIS Manager or appcmd)"
    }
}

function Set-IisSite {
    param($SiteName, $Port, $Pool, $PhysicalPath)

    $sitePath = "IIS:\Sites\$SiteName"
    if (-not (Test-Path $sitePath)) {
        New-Website -Name $SiteName -Port $Port -PhysicalPath $PhysicalPath -ApplicationPool $Pool | Out-Null
        Write-Host "  [OK] site '$SiteName' created on port $Port"
    } else {
        Write-Host "  [OK] site '$SiteName' already exists"
    }
}

function Set-FastCgiHandler {
    param($VenvPath)

    if (-not $VenvPath) {
        Write-Host "  [SKIP] no venv_path set in config.yaml for this project -- configure FastCGI (web.config) by hand"
        return
    }
    $pythonExe = Join-Path $VenvPath "Scripts\python.exe"
    $wfastcgiPy = Join-Path $VenvPath "Lib\site-packages\wfastcgi.py"
    if (-not (Test-Path $pythonExe)) {
        Write-Host "  [WARN] python.exe not found at $pythonExe -- check venv_path in config.yaml"
        return
    }

    $existing = Get-WebGlobalModule | Where-Object { $_.Name -eq "FastCGI" }
    if (-not $existing) {
        Write-Host "  [WARN] FastCGI module not installed in IIS -- enable the CGI/FastCGI Windows feature first"
    }

    $existingHandler = Get-WebConfiguration -Filter "system.webServer/fastCgi/application[@fullPath='$pythonExe']" -PSPath "MACHINE/WEBROOT/APPHOST" -ErrorAction SilentlyContinue
    if (-not $existingHandler) {
        Add-WebConfiguration -Filter "system.webServer/fastCgi" -Value @{
            fullPath = $pythonExe
            arguments = $wfastcgiPy
        } -PSPath "MACHINE/WEBROOT/APPHOST" | Out-Null
        Write-Host "  [OK] FastCGI application registered for $pythonExe"
    } else {
        Write-Host "  [OK] FastCGI application already registered for $pythonExe"
    }
}

function Setup-Project {
    param($Project)

    Write-Host "--- $($Project.name) ---"
    $iis = $Project.iis

    Set-IisAppPool -Pool $iis.app_pool -ServiceAccount $iis.service_account
    Set-IisSite -SiteName $iis.site_name -Port $iis.port -Pool $iis.app_pool -PhysicalPath $Project.path
    Set-FastCgiHandler -VenvPath $iis.venv_path
}

$config = Get-YamlConfig
$projects = $config.projects

if ($ProjectName) {
    $projects = $projects | Where-Object { $_.name -eq $ProjectName }
    if (-not $projects) {
        Write-Host "No project named '$ProjectName' in config.yaml"
        exit 1
    }
}

foreach ($project in $projects) {
    Setup-Project -Project $project
}

Write-Host "`nDone. web.config (handler mapping, routing) still needs to be placed in each"
Write-Host "project's folder by hand on the first deploy -- this script wires up the IIS"
Write-Host "site/pool/FastCGI registration, not each app's own web.config content."
