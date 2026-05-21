param(
    [switch]$SkipPackage,
    [switch]$KeepRunning,
    [int]$ProxyPort = 8000,
    [int]$ProxySslPort = 8443,
    [int]$AdminPort = 8001,
    [int]$StatusPort = 8100
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$postmanDir = $PSScriptRoot
$collection = Join-Path $postmanDir "Kong_3_4_2_Custom_Plugins.postman_collection.json"
$environment = Join-Path $postmanDir "local.postman_environment.json"
$rockDir = Join-Path $repoRoot "build/out"
$resultsDir = Join-Path $repoRoot "build/postman"
$resultsFile = Join-Path $resultsDir "newman-results.json"

Set-Location $repoRoot

function Test-PortAvailable {
    param([int]$Port)

    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($listeners) {
            return $false
        }
    }

    $listener = $null

    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($listener) {
            $listener.Stop()
        }
    }
}

function Get-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)

    try {
        $listener.Start()
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    } finally {
        $listener.Stop()
    }
}

function Resolve-Port {
    param(
        [string]$Name,
        [int]$PreferredPort
    )

    if (Test-PortAvailable -Port $PreferredPort) {
        return $PreferredPort
    }

    $freePort = Get-FreePort
    Write-Warning "$Name port $PreferredPort is already in use. Using $freePort for this run."
    return $freePort
}

function Invoke-CheckedCommand {
    param(
        [string]$Description,
        [scriptblock]$Command
    )

    Write-Host "----> $Description"
    & $Command

    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE"
    }
}

function Assert-PackagedRocks {
    $rocks = Get-ChildItem -Path $rockDir -Filter "*.rock" -ErrorAction SilentlyContinue

    if (-not $rocks) {
        throw "No .rock files found in build/out. Run 'docker compose run --rm --build plugin-packager' first, or rerun this script without -SkipPackage."
    }

    Write-Host "----> Found $($rocks.Count) packaged rock file(s)"
}

function Wait-ForKong {
    param([int]$Port)

    $statusUrl = "http://localhost:$Port/status"
    $deadline = (Get-Date).AddSeconds(90)

    Write-Host "----> Waiting for Kong at $statusUrl"

    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $statusUrl -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -eq 200) {
                Write-Host "----> Kong is ready"
                return
            }
        } catch {
            Start-Sleep -Seconds 2
        }
    }

    throw "Kong did not become ready within 90 seconds"
}

function Invoke-Newman {
    param(
        [int]$Proxy,
        [int]$Admin,
        [int]$Status
    )

    New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
    Remove-Item -LiteralPath $resultsFile -Force -ErrorAction SilentlyContinue

    Write-Host "----> Running collection with docker compose newman"
    & docker compose run --rm newman

    return $LASTEXITCODE
}

function Write-NewmanSummary {
    if (-not (Test-Path -LiteralPath $resultsFile)) {
        Write-Warning "Newman did not write $resultsFile"
        return
    }

    $results = Get-Content -Raw -LiteralPath $resultsFile | ConvertFrom-Json
    $stats = $results.run.stats
    $failureCount = @($results.run.failures).Count
    $failedRequests = if ($stats.requests.failed) { $stats.requests.failed } else { 0 }
    $failedAssertions = if ($stats.assertions.failed) { $stats.assertions.failed } else { 0 }
    $passedRequests = $stats.requests.total - $failedRequests
    $passedAssertions = $stats.assertions.total - $failedAssertions

    Write-Host ("----> Postman summary: requests={0}/{1}, assertions={2}/{3}, failures={4}" -f `
        $passedRequests, `
        $stats.requests.total, `
        $passedAssertions, `
        $stats.assertions.total, `
        $failureCount)
}

$exitCode = 1

try {
    $resolvedProxyPort = Resolve-Port -Name "Proxy" -PreferredPort $ProxyPort
    $resolvedProxySslPort = Resolve-Port -Name "Proxy SSL" -PreferredPort $ProxySslPort
    $resolvedAdminPort = Resolve-Port -Name "Admin API" -PreferredPort $AdminPort
    $resolvedStatusPort = Resolve-Port -Name "Status API" -PreferredPort $StatusPort

    $env:KONG_PROXY_PORT = [string]$resolvedProxyPort
    $env:KONG_PROXY_SSL_PORT = [string]$resolvedProxySslPort
    $env:KONG_ADMIN_PORT = [string]$resolvedAdminPort
    $env:KONG_STATUS_PORT = [string]$resolvedStatusPort

    Write-Host "----> Using ports: proxy=$resolvedProxyPort admin=$resolvedAdminPort status=$resolvedStatusPort"

    if (-not $SkipPackage) {
        Invoke-CheckedCommand "Packaging plugin rocks with docker compose" { docker compose run --rm --build plugin-packager }
    }

    Assert-PackagedRocks
    Invoke-CheckedCommand "Starting Kong with docker compose" { docker compose up -d --build }
    Wait-ForKong -Port $resolvedStatusPort
    $exitCode = Invoke-Newman -Proxy $resolvedProxyPort -Admin $resolvedAdminPort -Status $resolvedStatusPort
    Write-NewmanSummary
} catch {
    Write-Error $_
    $exitCode = 1
} finally {
    if (-not $KeepRunning) {
        Write-Host "----> Stopping docker compose services"
        docker compose down
    }
}

exit $exitCode
