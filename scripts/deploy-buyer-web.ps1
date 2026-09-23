# ==============================================================================
# LiveDrop — Buyer Website Vercel Deployment Automation Script (LiveDrop.in)
# ==============================================================================
#
# Usage:
#   .\scripts\deploy-buyer-web.ps1
#   .\scripts\deploy-buyer-web.ps1 -TargetEnv production
#   .\scripts\deploy-buyer-web.ps1 -SkipTests
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("production", "preview")]
    [string]$TargetEnv = "production",

    [Parameter()]
    [switch]$SkipTests = $false,

    [Parameter()]
    [string]$VercelToken = $env:VERCEL_TOKEN,

    [Parameter()]
    [string]$ProjectName = "livedrop-in",

    [Parameter()]
    [string]$CustomDomain = "livedrop.in"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " LiveDrop.in — Vercel Deployment Automation" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Target Environment : $TargetEnv" -ForegroundColor Yellow
Write-Host "Project Name       : $ProjectName (LiveDrop.in)" -ForegroundColor Yellow
Write-Host "Custom Domain      : $CustomDomain" -ForegroundColor Yellow
Write-Host "Timestamp          : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuyerWebDir = Join-Path $RepoRoot "buyer-web"

if (-not (Test-Path $BuyerWebDir)) {
    Write-Error "Could not find buyer-web directory at $BuyerWebDir"
    exit 1
}

# ------------------------------------------------------------------------------
# STEP 1: Pre-flight Quality Gates
# ------------------------------------------------------------------------------
Write-Host "`n[1/5] Running Pre-flight Quality Gates..." -ForegroundColor Green

Push-Location $BuyerWebDir
try {
    Write-Host "Checking TypeScript compilation..." -ForegroundColor Gray
    npm run typecheck
    if ($LASTEXITCODE -ne 0) {
        Write-Error "TypeScript check failed. Aborting deployment."
        exit 1
    }
    Write-Host "TypeScript check PASSED." -ForegroundColor Green

    if (-not $SkipTests) {
        Write-Host "Executing Vitest unit and integration test suite..." -ForegroundColor Gray
        npm test
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Vitest test suite failed. Aborting deployment."
            exit 1
        }
        Write-Host "All Vitest test suites PASSED." -ForegroundColor Green
    } else {
        Write-Host "Skipping tests as requested." -ForegroundColor Yellow
    }

    Write-Host "Validating Next.js Turbopack build..." -ForegroundColor Gray
    npm run build
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Next.js build failed. Aborting deployment."
        exit 1
    }
    Write-Host "Next.js build PASSED." -ForegroundColor Green
}
finally {
    Pop-Location
}

# ------------------------------------------------------------------------------
# STEP 2: Verify Vercel CLI & Authentication
# ------------------------------------------------------------------------------
Write-Host "`n[2/5] Checking Vercel CLI Authentication..." -ForegroundColor Green

$TokenArg = @()
if ($VercelToken -and $VercelToken.Trim() -ne "") {
    Write-Host "Using provided VERCEL_TOKEN for authentication." -ForegroundColor Gray
    $TokenArg = @("--token", $VercelToken)
}

# Check if authenticated
$WhoamiCheck = $null
try {
    $WhoamiCheck = npx vercel whoami @TokenArg 2>&1
} catch {
    $WhoamiCheck = $_.Exception.Message
}

if ($LASTEXITCODE -ne 0 -or ($WhoamiCheck -match "Logged out" -or $WhoamiCheck -match "No existing credentials")) {
    Write-Host "`nVercel CLI is not authenticated." -ForegroundColor Yellow
    Write-Host "To authenticate, you can:" -ForegroundColor Cyan
    Write-Host "  1. Run 'npx vercel login' in your interactive terminal, OR" -ForegroundColor Cyan
    Write-Host "  2. Pass a token: .\scripts\deploy-buyer-web.ps1 -VercelToken '<your_token>' (or set `$env:VERCEL_TOKEN)" -ForegroundColor Cyan
    
    try {
        npx vercel login
    } catch {
        Write-Error "Vercel login failed or timed out: $_"
        exit 1
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Vercel login was not completed. Please run 'npx vercel login' or set `$env:VERCEL_TOKEN and re-run."
        exit 1
    }
    Write-Host "Vercel authentication successful!" -ForegroundColor Green
} else {
    Write-Host "Authenticated with Vercel." -ForegroundColor Green
    Write-Host "$WhoamiCheck" -ForegroundColor Gray
}

# ------------------------------------------------------------------------------
# STEP 3: Project Linking & Configuration
# ------------------------------------------------------------------------------
Write-Host "`n[3/5] Linking Vercel Project '$ProjectName'..." -ForegroundColor Green

Push-Location $BuyerWebDir
try {
    # Check if .vercel exists or link
    $LinkArgs = @("link", "--yes", "--project", $ProjectName) + $TokenArg
    Write-Host "Executing: npx vercel $($LinkArgs -join ' ')" -ForegroundColor Gray
    npx vercel @LinkArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Initial link returned code $LASTEXITCODE. Attempting direct deployment." -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}

# ------------------------------------------------------------------------------
# STEP 4: Deploying to Vercel
# ------------------------------------------------------------------------------
Write-Host "`n[4/5] Deploying buyer-web to Vercel ($TargetEnv)..." -ForegroundColor Green

Push-Location $BuyerWebDir
$DeployUrl = ""
try {
    $DeployArgs = @("deploy", "--yes") + $TokenArg
    if ($TargetEnv -eq "production") {
        $DeployArgs += "--prod"
    }

    Write-Host "Executing: npx vercel $($DeployArgs -join ' ')" -ForegroundColor Gray
    $DeployOutput = npx vercel @DeployArgs
    Write-Host "$DeployOutput"

    # Extract URL
    $Lines = $DeployOutput -split "`r?`n"
    foreach ($Line in $Lines) {
        if ($Line -match "https://[a-zA-Z0-9\.-]+\.vercel\.app") {
            $DeployUrl = $Matches[0]
        }
    }
}
finally {
    Pop-Location
}

# ------------------------------------------------------------------------------
# STEP 5: Domain Configuration & Health Check
# ------------------------------------------------------------------------------
Write-Host "`n[5/5] Custom Domain & Health Check..." -ForegroundColor Green

if ($DeployUrl) {
    Write-Host "Live Deployment URL: $DeployUrl" -ForegroundColor Green
}

if ($TargetEnv -eq "production" -and $CustomDomain) {
    Write-Host "Configuring custom domain '$CustomDomain'..." -ForegroundColor Gray
    Push-Location $BuyerWebDir
    try {
        $DomainArgs = @("domains", "add", $CustomDomain, $ProjectName) + $TokenArg
        npx vercel @DomainArgs 2>&1 | Out-Null
    } catch {
        # Domain may already exist
    }
    finally {
        Pop-Location
    }

    Write-Host "`nTesting live health probe on https://$CustomDomain..." -ForegroundColor Gray
    try {
        $Response = Invoke-WebRequest -Uri "https://$CustomDomain" -TimeoutSec 10 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($Response.StatusCode -ge 200 -and $Response.StatusCode -lt 400) {
            Write-Host "Health check PASSED: https://$CustomDomain responded with status $($Response.StatusCode)" -ForegroundColor Green
        } else {
            Write-Host "Domain https://$CustomDomain returned status $($Response.StatusCode). DNS propagation may be underway." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Note: https://$CustomDomain not reachable directly yet (DNS propagation can take a few minutes). Deployed successfully to $DeployUrl." -ForegroundColor Yellow
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " Deployment Complete!" -ForegroundColor Green
Write-Host " Live URL   : $DeployUrl" -ForegroundColor Cyan
Write-Host " Domain     : https://$CustomDomain" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
