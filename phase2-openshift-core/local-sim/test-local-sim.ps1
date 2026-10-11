# ==============================================================================
# Script: test-local-sim.ps1
# Description: One-click local end-to-end integration test simulating OpenShift
#              Restricted SCC constraints using Docker.
# ==============================================================================

[CmdletBinding()]
param (
    [switch]$Cleanup,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir\..\.."
$ComposeFile = "$ScriptDir\docker-compose.ocp-sim.yml"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "OpenShift Restricted SCC Local Simulation Test" -ForegroundColor Cyan
Write-Host "Compose File: $ComposeFile" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

if ($Cleanup) {
    Write-Host "Stopping and removing simulation containers and volumes..." -ForegroundColor Yellow
    docker compose -f $ComposeFile down -v --remove-orphans
    exit 0
}

# 1. Build sample application images if missing
Write-Host "`n[1/5] Ensuring sample application images exist locally..." -ForegroundColor Green
$SamplesDir = "$ProjectRoot\phase1-local-poc\test-samples"
if (Test-Path $SamplesDir) {
    docker build -t custom-sample-payment-service:v1.0.0 $SamplesDir --quiet
    docker build -t custom-sample-payment-service:v1.1.0 $SamplesDir --quiet
    docker build -t custom-sample-auth-service:v2.0.0 $SamplesDir --quiet
    Write-Host "Sample images ready" -ForegroundColor DarkGreen
}

# 2. Build and start OpenShift-hardened infrastructure
Write-Host "`n[2/5] Starting OpenShift-hardened containers..." -ForegroundColor Green
if (-not $SkipBuild) {
    docker compose -f $ComposeFile build postgres dtrack-apiserver dtrack-frontend trivy-scanner
}
docker compose -f $ComposeFile up -d postgres dtrack-apiserver dtrack-frontend

# 3. Wait for API Server readiness
Write-Host "`n[3/5] Waiting for Dependency-Track API Server to be healthy..." -ForegroundColor Green
$MaxAttempts = 40
$Attempt = 0
$Healthy = $false
while ($Attempt -lt $MaxAttempts) {
    $Attempt++
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:18081/health/live" -TimeoutSec 3 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($resp -and $resp.status -eq "UP") {
            $Healthy = $true
            break
        }
    } catch {}
    Write-Host "  Attempt ${Attempt}/${MaxAttempts}: waiting for API server... (5s)" -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
}

if (-not $Healthy) {
    Write-Host "ERROR: Dependency-Track API Server failed to become healthy." -ForegroundColor Red
    docker compose -f $ComposeFile logs --tail 50 dtrack-apiserver
    exit 1
}
Write-Host "API Server is healthy!" -ForegroundColor DarkGreen

# 4. Bootstrap admin password and create Automation API Key
Write-Host "`n[4/5] Bootstrapping Dependency-Track authentication..." -ForegroundColor Green
[System.Net.WebRequest]::DefaultWebProxy = $null
$ApiKey = ""
try {
    $Token = ""
    # Try logging in with Admin12345! first
    try {
        $loginResp = Invoke-WebRequest -Uri "http://127.0.0.1:18081/api/v1/user/login" `
            -Method POST -Body "username=admin&password=Admin12345!" `
            -ContentType "application/x-www-form-urlencoded" -UseBasicParsing -ErrorAction Stop
        $Token = $loginResp.Content
    } catch {
        # If Admin12345! fails, try initial default admin/admin force-change
        try {
            $null = Invoke-WebRequest -Uri "http://127.0.0.1:18081/api/v1/user/forceChangePassword" `
                -Method POST -Body "username=admin&password=admin&newPassword=Admin12345!&confirmPassword=Admin12345!" `
                -ContentType "application/x-www-form-urlencoded" -UseBasicParsing -ErrorAction Stop
        } catch {}

        $loginResp = Invoke-WebRequest -Uri "http://127.0.0.1:18081/api/v1/user/login" `
            -Method POST -Body "username=admin&password=Admin12345!" `
            -ContentType "application/x-www-form-urlencoded" -UseBasicParsing -ErrorAction Stop
        $Token = $loginResp.Content
    }

    $AuthHeader = @{ "Authorization" = "Bearer $Token" }
    $teams = Invoke-RestMethod -Uri "http://127.0.0.1:18081/api/v1/team" -Headers $AuthHeader
    $autoTeam = $teams | Where-Object { $_.name -eq "Automation" }
    if (-not $autoTeam) {
        Write-Host "  Creating Automation team..." -ForegroundColor DarkGray
        $autoTeam = Invoke-RestMethod -Uri "http://127.0.0.1:18081/api/v1/team" `
            -Method PUT -Headers $AuthHeader -ContentType "application/json" `
            -Body '{"name":"Automation"}'
    }

    $perms = @("BOM_UPLOAD", "PROJECT_CREATION_UPLOAD", "PORTFOLIO_MANAGEMENT", "VIEW_PORTFOLIO", "VIEW_VULNERABILITY", "VULNERABILITY_ANALYSIS")
    foreach ($p in $perms) {
        try {
            Invoke-RestMethod -Uri "http://127.0.0.1:18081/api/v1/permission/$p/team/$($autoTeam.uuid)" `
                -Method POST -Headers $AuthHeader -ContentType "application/json" -ErrorAction SilentlyContinue | Out-Null
        } catch {}
    }

    if ($autoTeam.apiKeys -and $autoTeam.apiKeys.Count -gt 0) {
        $ApiKey = $autoTeam.apiKeys[0].key
    } else {
        $keyResp = Invoke-RestMethod -Uri "http://127.0.0.1:18081/api/v1/team/$($autoTeam.uuid)/key" `
            -Method PUT -Headers $AuthHeader
        $ApiKey = $keyResp.key
    }
    Write-Host "Automation API Key ready: $($ApiKey.Substring(0, 8))..." -ForegroundColor DarkGreen
} catch {
    Write-Host "ERROR: Failed during auth bootstrap: $_" -ForegroundColor Red
    exit 1
}

# 5. Run Ephemeral Scanner Worker Simulation
Write-Host "`n[5/5] Running Phase 3 Scanner Job Simulation (Auto-Discovery mode)..." -ForegroundColor Green
$env:DTRACK_API_KEY = $ApiKey
$env:TARGET_IMAGE = "ALL"
$scanExit = 0
try {
    docker compose -f $ComposeFile run --rm `
        -e "DTRACK_API_KEY=$ApiKey" `
        -e "TARGET_IMAGE=ALL" `
        trivy-scanner
    $scanExit = $LASTEXITCODE
} catch {
    $scanExit = 1
}

Write-Host "`n=================================================================" -ForegroundColor Cyan
if ($scanExit -eq 0) {
    Write-Host "Simulation test PASSED! OpenShift manifests and images verified." -ForegroundColor Green
    Write-Host "Frontend URL: http://localhost:18080 (admin / Admin12345!)" -ForegroundColor Green
    Write-Host "API Server:   http://localhost:18081" -ForegroundColor Green
} else {
    Write-Host "Simulation test FAILED with exit code $scanExit." -ForegroundColor Red
}
Write-Host "=================================================================" -ForegroundColor Cyan

exit $scanExit
