# Postman Smoke Tests

This folder has two Postman/Newman suites:

| Collection | Runner | Purpose |
| --- | --- | --- |
| `Kong_3_4_2_Custom_Plugins.postman_collection.json` | `run-collection.ps1` | Validates Kong, the custom plugins, and the local echo upstream |
| `Keycloak_SAML_IdP.postman_collection.json` | `run-keycloak-saml-collection.ps1` | Validates the optional Keycloak SAML IdP realm, SAML endpoints, and signing config |

## Kong Plugin Collection

The Kong collection validates the local Kong 3.4.2 setup end to end:

- Kong status and Admin API are reachable.
- Kong reports version `3.4.2`.
- The custom plugins are enabled.
- `request-profiler` adds correlation and timing headers.
- `canary-header-router` forces stable/canary tracks with headers.
- `json-field-guard` accepts valid JSON and rejects missing, forbidden, or non-JSON payloads.

## Run Everything

From the repo root:

```powershell
.\tests\postman\run-collection.ps1
```

The script:

1. Runs `docker compose run --rm plugin-packager`.
2. Confirms `.rock` files exist in `build/out`.
3. Starts `docker compose up -d --build`.
4. Auto-picks free host ports if the default Kong ports are already busy.
5. Waits for the Kong status endpoint.
6. Runs the Postman collection with the Compose `newman` service.
7. Stops the Compose stack unless `-KeepRunning` is passed.

Newman runs in Docker through Compose, so local `newman` or `npx` is not required.

## Useful Options

```powershell
.\tests\postman\run-collection.ps1 -SkipPackage
.\tests\postman\run-collection.ps1 -KeepRunning
.\tests\postman\run-collection.ps1 -ProxyPort 18000 -AdminPort 18001 -StatusPort 18100
```

## Manual Postman Use

Import both files:

- `Kong_3_4_2_Custom_Plugins.postman_collection.json`
- `local.postman_environment.json`

Then select the `Kong 3.4.2 Local` environment and run the collection.

## Keycloak SAML Collection

From the repo root:

```powershell
.\tests\postman\run-keycloak-saml-collection.ps1
```

The script:

1. Starts `keycloak` with `docker compose --profile idp up -d keycloak`.
2. Waits for the realm SAML metadata endpoint.
3. Runs `Keycloak_SAML_IdP.postman_collection.json` with the Compose `newman` service.
4. Writes results to `build/postman/keycloak-saml-newman-results.json`.
5. Stops Keycloak unless it was already running or `-KeepRunning` is passed.

Useful options:

```powershell
.\tests\postman\run-keycloak-saml-collection.ps1 -KeepRunning
.\tests\postman\run-keycloak-saml-collection.ps1 -KeycloakPort 18080
.\tests\postman\run-keycloak-saml-collection.ps1 -AdminUsername admin -AdminPassword admin
```

The Keycloak collection checks:

- SAML metadata descriptor is published.
- Signing certificate appears in metadata.
- HTTP-POST, HTTP-Redirect, SOAP, SSO, SLO, and artifact endpoints appear in metadata.
- IdP-initiated SSO login page is reachable.
- Empty or malformed SAML protocol requests are rejected.
- The imported SAML client has signed Response and signed Assertion enabled.
- `RSA_SHA256`, one-time-use condition, ACS URL, logout URL, and SAML attribute mappers are configured.

For manual Postman use, import:

- `Keycloak_SAML_IdP.postman_collection.json`
- `keycloak.postman_environment.json`

Then start Keycloak with:

```powershell
docker compose --profile idp up -d keycloak
```

Select the `Keycloak SAML Local` environment and run the collection.
