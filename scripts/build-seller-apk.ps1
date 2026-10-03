# ==============================================================================
# LiveDrop — Seller Mobile App Release Build Script
# ==============================================================================
#
# Builds a SIGNED release APK (and optionally an App Bundle) for the LiveDrop
# Seller Flutter App. Release builds are only produced when release signing is
# configured; they are never signed with the debug key (SA-AND-001).
#
# Release signing (one of):
#   * seller-app/android/key.properties (gitignored):
#       storeFile=C:/secure/livedrop-upload-keystore.jks
#       storePassword=...
#       keyAlias=livedrop-upload
#       keyPassword=...
#   * environment variables LIVEDROP_KEYSTORE_PATH, LIVEDROP_KEYSTORE_PASSWORD,
#     LIVEDROP_KEY_ALIAS, LIVEDROP_KEY_PASSWORD
# See docs/ops/android-release-signing.md.
#
# Usage:
#   .\scripts\build-seller-apk.ps1
#   .\scripts\build-seller-apk.ps1 -SplitPerAbi
#   .\scripts\build-seller-apk.ps1 -AppBundle -BuildNumber 42
#   .\scripts\build-seller-apk.ps1 -TargetEnv staging
#   .\scripts\build-seller-apk.ps1 -SkipTests
#   .\scripts\build-seller-apk.ps1 -CheckSigningOnly
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("production", "staging", "development")]
    [string]$TargetEnv = "production",

    [Parameter()]
    [switch]$SplitPerAbi = $false,

    [Parameter()]
    [switch]$AppBundle = $false,

    [Parameter()]
    [ValidateRange(0, 2100000000)]
    [int]$BuildNumber = 0,

    [Parameter()]
    [switch]$SkipTests = $false,

    [Parameter()]
    [switch]$CheckSigningOnly = $false,

    [Parameter()]
    [string]$SupabaseUrl = "",

    [Parameter()]
    [string]$SupabaseAnonKey = "",

    [Parameter()]
    [string]$BuyerBaseUrl = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SellerAppDir = Join-Path $RepoRoot "seller-app"
$AndroidDir = Join-Path $SellerAppDir "android"
$KeyPropertiesPath = Join-Path $AndroidDir "key.properties"
$BuyerWebEnvLocal = Join-Path $RepoRoot "buyer-web\.env.local"

function Resolve-StorePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    # key.properties is a java.util.Properties file: "\\" is an escaped backslash.
    $trimmed = $Path.Trim().Replace('\\', '\')
    if ([System.IO.Path]::IsPathRooted($trimmed)) { return $trimmed }
    # Same rule as android/app/build.gradle.kts: relative to seller-app/android.
    return (Join-Path $AndroidDir $trimmed)
}

# Returns @{ Source; Problems } describing the release signing configuration.
# Never returns or prints password values.
function Get-ReleaseSigningStatus {
    $problems = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $KeyPropertiesPath -PathType Leaf) {
        $source = "key.properties ($KeyPropertiesPath)"
        $props = @{}
        foreach ($rawLine in Get-Content -LiteralPath $KeyPropertiesPath) {
            $line = $rawLine.Trim()
            if ($line -eq "" -or $line.StartsWith("#") -or $line.StartsWith("!")) { continue }
            $match = [regex]::Match($line, '^([^=:\s]+)\s*[=:]\s*(.*)$')
            if ($match.Success) { $props[$match.Groups[1].Value] = $match.Groups[2].Value }
        }
        $storeFile = Resolve-StorePath $props["storeFile"]
        if (-not $storeFile) { $problems.Add("storeFile is missing in key.properties") }
        elseif (-not (Test-Path -LiteralPath $storeFile -PathType Leaf)) { $problems.Add("keystore file does not exist: $storeFile") }
        foreach ($key in @("storePassword", "keyAlias", "keyPassword")) {
            if ([string]::IsNullOrWhiteSpace($props[$key])) { $problems.Add("$key is missing in key.properties") }
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($env:LIVEDROP_KEYSTORE_PATH)) {
        $source = "LIVEDROP_* environment variables"
        $storeFile = Resolve-StorePath $env:LIVEDROP_KEYSTORE_PATH
        if (-not (Test-Path -LiteralPath $storeFile -PathType Leaf)) { $problems.Add("keystore file does not exist: $storeFile") }
        foreach ($name in @("LIVEDROP_KEYSTORE_PASSWORD", "LIVEDROP_KEY_ALIAS", "LIVEDROP_KEY_PASSWORD")) {
            if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) { $problems.Add("$name is not set") }
        }
    } else {
        $source = "none"
        $problems.Add("no seller-app/android/key.properties and no LIVEDROP_KEYSTORE_PATH environment variable")
    }
    return @{ Source = $source; Problems = $problems }
}

function Write-SigningHelp {
    Write-Host ""
    Write-Host "Release signing is not configured. A release build is only produced with the LiveDrop upload key." -ForegroundColor Red
    Write-Host "Configure ONE of the following, then re-run this script:" -ForegroundColor Yellow
    Write-Host "  1. Create seller-app\android\key.properties (gitignored, never commit it):" -ForegroundColor Yellow
    Write-Host "       storeFile=C:/secure/livedrop-upload-keystore.jks"
    Write-Host "       storePassword=<keystore password>"
    Write-Host "       keyAlias=livedrop-upload"
    Write-Host "       keyPassword=<key password>"
    Write-Host "  2. Or set environment variables for this shell:" -ForegroundColor Yellow
    Write-Host "       `$env:LIVEDROP_KEYSTORE_PATH, `$env:LIVEDROP_KEYSTORE_PASSWORD, `$env:LIVEDROP_KEY_ALIAS, `$env:LIVEDROP_KEY_PASSWORD"
    Write-Host "  How to create and back up the upload keystore: docs/ops/android-release-signing.md" -ForegroundColor Yellow
    Write-Host "  For a test build without the release key use: flutter build apk --debug" -ForegroundColor Gray
}

# Prints the signer of an APK/AAB and fails on the Android debug certificate.
function Assert-ReleaseCertificate([string]$ArtifactPath) {
    $sdkRoot = $env:ANDROID_HOME
    if ([string]::IsNullOrWhiteSpace($sdkRoot)) { $sdkRoot = $env:ANDROID_SDK_ROOT }
    $apksigner = $null
    if ($ArtifactPath.EndsWith(".apk") -and $sdkRoot -and (Test-Path (Join-Path $sdkRoot "build-tools"))) {
        $buildTools = Get-ChildItem -Path (Join-Path $sdkRoot "build-tools") -Directory |
            Sort-Object { try { [version]$_.Name } catch { [version]"0.0" } } |
            Select-Object -Last 1
        if ($buildTools) {
            foreach ($candidate in @("apksigner.bat", "apksigner")) {
                $path = Join-Path $buildTools.FullName $candidate
                if (Test-Path $path) { $apksigner = $path; break }
            }
        }
    }
    if ($apksigner) {
        $output = & $apksigner verify --print-certs $ArtifactPath 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "apksigner could not verify $ArtifactPath`n$output" }
    } else {
        $output = & keytool -printcert -jarfile $ArtifactPath 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $output -notmatch "SHA256") { throw "Could not read the signing certificate of $ArtifactPath`n$output" }
    }
    $signerLines = ($output -split "`r?`n") | Where-Object { $_ -match "certificate DN:|certificate SHA-256 digest:|^Owner:|^\s*SHA256:" }
    $signerLines | ForEach-Object { Write-Host "   $($_.Trim())" -ForegroundColor Gray }
    if ($output -match "CN=Android Debug") {
        throw "$ArtifactPath is signed with the Android DEBUG certificate. Do not distribute it."
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " LiveDrop - Seller App Release Build Tool" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Target Environment : $TargetEnv" -ForegroundColor Yellow
Write-Host "Split per ABI      : $SplitPerAbi" -ForegroundColor Yellow
Write-Host "App Bundle         : $AppBundle" -ForegroundColor Yellow
Write-Host "Build number       : $(if ($BuildNumber -gt 0) { $BuildNumber } else { 'from pubspec.yaml' })" -ForegroundColor Yellow
Write-Host "Timestamp          : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-Path $SellerAppDir)) {
    Write-Error "Could not find seller-app directory at $SellerAppDir"
    exit 1
}

# Step 0: release signing must be configured before anything else runs.
$signing = Get-ReleaseSigningStatus
if ($signing.Problems.Count -gt 0) {
    Write-Host "Release signing source: $($signing.Source)" -ForegroundColor Red
    $signing.Problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-SigningHelp
    exit 1
}
Write-Host "Release signing    : $($signing.Source)" -ForegroundColor Green
if ($CheckSigningOnly) {
    Write-Host "Release signing is configured (-CheckSigningOnly: nothing built)." -ForegroundColor Green
    exit 0
}

# Resolve Supabase URL & Anon Key from parameters, env, or buyer-web/.env.local fallback
if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
    $SupabaseUrl = $env:SUPABASE_URL
}
if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
    $SupabaseAnonKey = $env:SUPABASE_ANON_KEY
}
if ([string]::IsNullOrWhiteSpace($BuyerBaseUrl)) {
    $BuyerBaseUrl = $env:BUYER_BASE_URL
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
if (-not [string]::IsNullOrWhiteSpace($BuyerBaseUrl)) {
    Write-Host "Buyer base URL     : $BuyerBaseUrl" -ForegroundColor Gray
}

Push-Location $SellerAppDir
try {
    # Step 1: Pre-flight Verification
    if (-not $SkipTests) {
        Write-Host "`n[1/4] Running Flutter static analysis..." -ForegroundColor Green
        flutter analyze
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Flutter analysis failed. Aborting build."
            exit 1
        }

        Write-Host "`n[2/4] Running Flutter test suite..." -ForegroundColor Green
        flutter test
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Flutter tests failed. Aborting build."
            exit 1
        }
    } else {
        Write-Host "`n[Skipping static analysis & tests due to -SkipTests]" -ForegroundColor Yellow
    }

    $commonArgs = @(
        "--release",
        "--dart-define=SUPABASE_URL=$SupabaseUrl",
        "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey",
        "--dart-define=APP_ENV=$TargetEnv"
    )
    if (-not [string]::IsNullOrWhiteSpace($BuyerBaseUrl)) {
        $commonArgs += "--dart-define=BUYER_BASE_URL=$BuyerBaseUrl"
    }
    if ($BuildNumber -gt 0) {
        $commonArgs += "--build-number=$BuildNumber"
    }

    # Step 2: Build signed release APK (and optionally the App Bundle)
    Write-Host "`n[3/4] Compiling signed Flutter release build..." -ForegroundColor Green

    $apkArgs = @("build", "apk") + $commonArgs
    if ($SplitPerAbi) {
        $apkArgs += "--split-per-abi"
    }
    & flutter @apkArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter release APK build failed."
        exit 1
    }

    if ($AppBundle) {
        $bundleArgs = @("build", "appbundle") + $commonArgs
        & flutter @bundleArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Flutter release App Bundle build failed."
            exit 1
        }
    }

    # Step 3: Verify the artifacts are signed with the release key, not the debug key
    Write-Host "`n[4/4] Verifying signing certificate..." -ForegroundColor Green
    $outputDir = Join-Path $SellerAppDir "build\app\outputs\flutter-apk"
    $apks = @(Get-ChildItem -Path $outputDir -Filter "*release*.apk")
    if ($apks.Count -eq 0) {
        Write-Error "No release APK found in $outputDir"
        exit 1
    }
    $artifacts = @($apks)
    if ($AppBundle) {
        $artifacts += Get-ChildItem -Path (Join-Path $SellerAppDir "build\app\outputs\bundle\release") -Filter "*.aab"
    }
    foreach ($artifact in $artifacts) {
        Write-Host " $($artifact.Name)" -ForegroundColor Cyan
        Assert-ReleaseCertificate $artifact.FullName
    }

    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host " Build Complete! Artifacts:" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    foreach ($artifact in $artifacts) {
        $sizeMB = [math]::Round($artifact.Length / 1MB, 2)
        Write-Host " $($artifact.FullName) ($sizeMB MB)" -ForegroundColor Cyan
    }
    Write-Host "==========================================================" -ForegroundColor Green
}
finally {
    Pop-Location
}
