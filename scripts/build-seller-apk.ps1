# ==============================================================================
# LiveDrop — Seller Mobile App Release APK Build Script
# ==============================================================================
#
# Builds the production or staging release APK for the LiveDrop Seller Flutter App.
#
# Usage:
#   .\scripts\build-seller-apk.ps1
#   .\scripts\build-seller-apk.ps1 -SplitPerAbi
#   .\scripts\build-seller-apk.ps1 -TargetEnv staging
#   .\scripts\build-seller-apk.ps1 -SkipTests
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("production", "staging", "development")]
    [string]$TargetEnv = "production",

    [Parameter()]
    [switch]$SplitPerAbi = $false,

    [Parameter()]
    [switch]$SkipTests = $false,

    [Parameter()]
    [string]$SupabaseUrl = "",

    [Parameter()]
    [string]$SupabaseAnonKey = ""
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " LiveDrop — Seller App Release APK Build Tool" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Target Environment : $TargetEnv" -ForegroundColor Yellow
Write-Host "Split per ABI      : $SplitPerAbi" -ForegroundColor Yellow
Write-Host "Timestamp          : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SellerAppDir = Join-Path $RepoRoot "seller-app"
$BuyerWebEnvLocal = Join-Path $RepoRoot "buyer-web\.env.local"

if (-not (Test-Path $SellerAppDir)) {
    Write-Error "Could not find seller-app directory at $SellerAppDir"
    exit 1
}

# Resolve Supabase URL & Anon Key from parameters, env, or buyer-web/.env.local fallback
if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
    $SupabaseUrl = $env:SUPABASE_URL
}
if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
    $SupabaseAnonKey = $env:SUPABASE_ANON_KEY
}

if (([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($SupabaseAnonKey)) -and (Test-Path $BuyerWebEnvLocal)) {
    Write-Host "Resolving Supabase credentials from $BuyerWebEnvLocal..." -ForegroundColor Gray
    Get-Content $BuyerWebEnvLocal | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^NEXT_PUBLIC_SUPABASE_URL\s*=\s*(.+)$') {
            if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
                $SupabaseUrl = $matches[1].Trim("'", '"', ' ')
            }
        }
        if ($line -match '^NEXT_PUBLIC_SUPABASE_ANON_KEY\s*=\s*(.+)$') {
            if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
                $SupabaseAnonKey = $matches[1].Trim("'", '"', ' ')
            }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
    $SupabaseUrl = "https://aoagqdtnrbmayfoajzes.supabase.co"
}

if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
    Write-Error "Missing SUPABASE_ANON_KEY. Please provide via -SupabaseAnonKey or set `$env:SUPABASE_ANON_KEY"
    exit 1
}

Write-Host "Supabase URL       : $SupabaseUrl" -ForegroundColor Gray
Write-Host "Supabase Key       : $($SupabaseAnonKey.Substring(0, [Math]::Min(12, $SupabaseAnonKey.Length)))..." -ForegroundColor Gray

Push-Location $SellerAppDir
try {
    # Step 1: Pre-flight Verification
    if (-not $SkipTests) {
        Write-Host "`n[1/3] Running Flutter static analysis..." -ForegroundColor Green
        flutter analyze
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Flutter analysis failed. Aborting build."
            exit 1
        }

        Write-Host "`n[2/3] Running Flutter test suite..." -ForegroundColor Green
        flutter test
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Flutter tests failed. Aborting build."
            exit 1
        }
    } else {
        Write-Host "`n[Skipping static analysis & tests due to -SkipTests]" -ForegroundColor Yellow
    }

    # Step 2: Build Release APK
    Write-Host "`n[3/3] Compiling Flutter Release APK..." -ForegroundColor Green
    
    $buildArgs = @(
        "build", "apk", "--release",
        "--dart-define=SUPABASE_URL=$SupabaseUrl",
        "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey",
        "--dart-define=APP_ENV=$TargetEnv"
    )

    if ($SplitPerAbi) {
        $buildArgs += "--split-per-abi"
    }

    & flutter @buildArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter release APK build failed."
        exit 1
    }

    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host " Build Complete! Artifacts:" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    $outputDir = Join-Path $SellerAppDir "build\app\outputs\flutter-apk"
    Get-ChildItem -Path $outputDir -Filter "*release*.apk" | ForEach-Object {
        $sizeMB = [math]::Round($_.Length / 1MB, 2)
        Write-Host " APK File : $($_.FullName) ($sizeMB MB)" -ForegroundColor Cyan
    }
    Write-Host "==========================================================" -ForegroundColor Green
}
finally {
    Pop-Location
}
