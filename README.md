# Kong Plugins Builder

This project packages local Lua Kong plugins as LuaRocks `.rock` files and runs them in a local Kong Gateway 3.4.2 container.

## Layout

- `custom-plugins/` contains the Lua plugin source and one rockspec per plugin.
- `build/out/` is created by `make package` and contains the packaged `.rock` files.
- `kong/kong.yml` is the DB-less Kong declarative config that enables the plugins.
- `docker-compose.yml` starts Kong 3.4.2 and mounts `build/out` into the container.

## Package Plugins

```sh
make package
```

The Makefile uses:

```make
PONGO_VERSION := 2.12.0
KONG_VERSION := 2.8.4.11
```

Each plugin under `custom-plugins/` is packed independently. The generated rocks are moved into `build/out/`.

## Run Kong 3.4.2

```sh
docker compose up --build
```

The Kong container installs every `.rock` file from `build/out` before launching Kong. If `build/out` is empty, the container exits and asks you to run `make package`.

Useful endpoints:

- Proxy: `http://localhost:8000`
- Admin API: `http://localhost:8001`
- Status API: `http://localhost:8100/status`

## Included Plugins

- `request-profiler`: adds request correlation and elapsed-time response headers, and logs a request summary.
- `json-field-guard`: validates JSON request bodies for required fields and forbidden keys.
- `canary-header-router`: deterministically assigns traffic to `stable` or `canary` release tracks using a sticky request header.

## Smoke Tests

Request timing and canary headers:

```sh
curl -i http://localhost:8000/anything/get
```

Force canary routing:

```sh
curl -i -H "X-Canary-Override: canary" http://localhost:8000/anything/headers
```

Valid guarded JSON:

```sh
curl -i -X POST http://localhost:8000/guarded/post \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"cust-123","action":"signup"}'
```

Rejected guarded JSON:

```sh
curl -i -X POST http://localhost:8000/guarded/post \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"cust-123","password":"secret"}'
```
