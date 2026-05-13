# Postman Smoke Tests

The collection validates the local Kong 3.4.2 setup end to end:

- Kong status and Admin API are reachable.
- Kong reports version `3.4.2`.
- The custom plugins are enabled.
- `request-profiler` adds correlation and timing headers.
- `canary-header-router` forces stable/canary tracks with headers.
- `json-field-guard` accepts valid JSON and rejects missing, forbidden, or non-JSON payloads.

## Run Everything

From the repo root:

```powershell
.\postman\run-collection.ps1
```

The script:

1. Runs `make package` when `make` is available.
2. Confirms `.rock` files exist in `build/out`.
3. Starts `docker compose up -d --build`.
4. Auto-picks free host ports if the default Kong ports are already busy.
5. Waits for the Kong status endpoint.
6. Runs the Postman collection with Newman.
7. Stops the Compose stack unless `-KeepRunning` is passed.

If `newman` is not installed locally, the script falls back to the `postman/newman:alpine` Docker image.

## Useful Options

```powershell
.\postman\run-collection.ps1 -SkipPackage
.\postman\run-collection.ps1 -KeepRunning
.\postman\run-collection.ps1 -UseDockerNewman
.\postman\run-collection.ps1 -ProxyPort 18000 -AdminPort 18001 -StatusPort 18100
```

## Manual Postman Use

Import both files:

- `Kong_3_4_2_Custom_Plugins.postman_collection.json`
- `local.postman_environment.json`

Then select the `Kong 3.4.2 Local` environment and run the collection.
