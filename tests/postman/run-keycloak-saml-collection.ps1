param(
    [switch]$KeepRunning,
    [int]$KeycloakPort = 18080,
    [string]$AdminUsername = $(if ($env:KEYCLOAK_ADMIN) { $env:KEYCLOAK_ADMIN } else { "admin" }),
    [string]$AdminPassword = $(if ($env:KEYCLOAK_ADMIN_PASSWORD) { $env:KEYCLOAK_ADMIN_PASSWORD } else { "admin" })
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$postmanDir = $PSScriptRoot
$collection = Join-Path $postmanDir "Keycloak_SAML_IdP.postman_collection.json"
$environment = Join-Path $postmanDir "keycloak.postman_environment.json"
$resultsDir = Join-Path $repoRoot "build/postman"
$resultsFile = Join-Path $resultsDir "keycloak-saml-newman-results.json"

Set-Location $repoRoot

function Test-KeycloakRunning {
    $services = docker compose --profile idp ps --status running --services
    return @($services) -contains "keycloak"
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

function Wait-ForKeycloak {
    param([int]$Port)

    $metadataUrl = "http://localhost:$Port/realms/kong-plugin-lab/protocol/saml/descriptor"
    $deadline = (Get-Date).AddSeconds(120)

    Write-Host "----> Waiting for Keycloak at $metadataUrl"

    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $metadataUrl -UseBasicParsing -TimeoutSec 3
            if ($response.StatusCode -eq 200 -and $response.Content -match "EntityDescriptor") {
                Write-Host "----> Keycloak SAML metadata is ready"
                return
            }
        } catch {
            Start-Sleep -Seconds 3
        }
    }

    throw "Keycloak SAML metadata did not become ready within 120 seconds"
}

function Invoke-Newman {
    New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
    Remove-Item -LiteralPath $resultsFile -Force -ErrorAction SilentlyContinue

    Write-Host "----> Running Keycloak SAML collection with docker compose newman"
    & docker compose run --rm --no-deps newman `
        run /etc/newman/Keycloak_SAML_IdP.postman_collection.json `
        -e /etc/newman/keycloak.postman_environment.json `
        --env-var "keycloak_url=http://keycloak:8080" `
        --env-var "admin_username=$AdminUsername" `
        --env-var "admin_password=$AdminPassword" `
        --reporters cli,json `
        --reporter-json-export /etc/newman-results/keycloak-saml-newman-results.json `
        --color on

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

    Write-Host ("----> Keycloak SAML summary: requests={0}/{1}, assertions={2}/{3}, failures={4}" -f `
        $passedRequests, `
        $stats.requests.total, `
        $passedAssertions, `
        $stats.assertions.total, `
        $failureCount)
}

$keycloakWasRunning = Test-KeycloakRunning
$exitCode = 1

try {
    $env:KEYCLOAK_PORT = [string]$KeycloakPort
    $env:KEYCLOAK_ADMIN = $AdminUsername
    $env:KEYCLOAK_ADMIN_PASSWORD = $AdminPassword

    Invoke-CheckedCommand "Starting Keycloak with docker compose" { docker compose --profile idp up -d keycloak }
    Wait-ForKeycloak -Port $KeycloakPort
    $exitCode = Invoke-Newman
    Write-NewmanSummary
} catch {
    Write-Error $_
    $exitCode = 1
} finally {
    if (-not $KeepRunning -and -not $keycloakWasRunning) {
        Write-Host "----> Stopping Keycloak"
        docker compose --profile idp stop keycloak
        docker compose --profile idp rm -f keycloak
    }
}

exit $exitCode
