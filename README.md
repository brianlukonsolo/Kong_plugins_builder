# 🟦 Kong Plugins Builder

![Kong](https://img.shields.io/badge/Kong%20Gateway-3.4.2-00A3E0)
![Docker Compose](https://img.shields.io/badge/Docker%20Compose-required-2496ED)
![LuaRocks](https://img.shields.io/badge/plugins-.rock%20files-2ECC71)
![Postman](https://img.shields.io/badge/Postman%20tests-automated-FF6C37)

This repo is a local, containerized Kong plugin lab.

In plain English: you put Lua Kong plugins into `custom-plugins/`, run `make package`, and the repo turns those plugins into LuaRocks `.rock` files. Then `docker compose up --build` starts Kong Gateway `3.4.2`, automatically installs those `.rock` files, loads the plugins, and exposes Kong locally.

The sample plugins are only examples. For work, you will replace them with your real plugins but keep the same packaging and runtime pattern.

For the deeper implementation details, read [`TECHNICAL_README.md`](TECHNICAL_README.md). It explains exactly how plugins are built, installed, enabled, and configured.

## 🟢 Quick Start

Package the plugins:

```sh
make package
```

Start Kong:

```sh
docker compose up --build
```

Run the automated Postman/Newman tests:

```powershell
.\postman\run-collection.ps1
```

Useful local URLs:

| Purpose | URL |
| --- | --- |
| 🟢 Kong proxy | `http://localhost:8000` |
| 🔵 Kong Admin API | `http://localhost:8001` |
| 🟣 Kong status API | `http://localhost:8100/status` |

If port `8000` is already busy, the Postman runner automatically chooses a free port for that test run.

## 🧠 Big Picture

The repo has two separate jobs:

| Job | Tool | What It Does |
| --- | --- | --- |
| 📦 Build plugins | `make package` + Pongo | Converts Lua plugin folders into `.rock` files |
| 🚀 Run Kong locally | Docker Compose | Starts Kong `3.4.2` and installs those `.rock` files |

Important version note:

```make
PONGO_VERSION := 2.12.0
KONG_VERSION := 2.8.4.11
```

Those values are used by the Makefile/Pongo packaging flow because that is what was requested. The actual local Kong runtime is:

```yaml
image: local/kong-plugins-builder:3.4.2
```

So keep these ideas separate:

- 🟨 `KONG_VERSION := 2.8.4.11` in the Makefile controls the Pongo build environment.
- 🟦 `kong:3.4.2` in Docker controls the local Kong Gateway runtime.

## 📁 Repo Layout

```text
.
├── custom-plugins/
│   ├── request-profiler/
│   ├── json-field-guard/
│   └── canary-header-router/
├── build/out/
├── docker/
│   ├── kong.Dockerfile
│   ├── kong-install-rocks.sh
│   ├── echo-server.Dockerfile
│   └── echo-server.py
├── kong/
│   └── kong.yml
├── postman/
│   ├── Kong_3_4_2_Custom_Plugins.postman_collection.json
│   ├── local.postman_environment.json
│   ├── run-collection.ps1
│   └── README.md
├── docker-compose.yml
├── Makefile
└── README.md
```

What each folder means:

| Path | Meaning |
| --- | --- |
| 🟢 `custom-plugins/` | The actual Lua Kong plugin source lives here |
| 🟡 `build/out/` | Generated `.rock` files land here after `make package` |
| 🔵 `docker/` | Docker image files and helper scripts |
| 🟣 `kong/kong.yml` | Kong DB-less config: services, routes, and enabled plugin instances |
| 🟠 `postman/` | Automated smoke tests for the whole setup |
| ⚪ `src/` | Existing Maven archetype files; not used by the Kong runtime |

## 🔁 Full Flow

Here is the whole system from left to right:

```text
Lua plugin source
      ↓
custom-plugins/<plugin-name>/
      ↓
make package
      ↓
build/out/*.rock
      ↓
docker compose up --build
      ↓
Kong container starts
      ↓
docker/kong-install-rocks.sh installs every .rock file
      ↓
Kong loads plugins listed in KONG_PLUGINS
      ↓
kong/kong.yml attaches plugin configs to routes/services/globally
      ↓
Postman/Newman confirms everything works
```

## 📦 How Plugin Packaging Works

Each plugin folder is a mini LuaRocks project.

Example:

```text
custom-plugins/request-profiler/
├── kong-plugin-request-profiler-0.1.0-1.rockspec
└── kong/
    └── plugins/
        └── request-profiler/
            ├── handler.lua
            └── schema.lua
```

The Makefile finds every folder under `custom-plugins/` that contains a `.rockspec` file:

```make
PLUGIN_DIRS := $(wildcard custom-plugins/*)
```

Then this command packages them:

```sh
make package
```

That creates:

```text
build/out/kong-plugin-request-profiler-0.1.0-1.all.rock
build/out/kong-plugin-json-field-guard-0.1.0-1.all.rock
build/out/kong-plugin-canary-header-router-0.1.0-1.all.rock
```

🟡 `build/out/` is generated output. Do not edit those files by hand.

## 🧩 Anatomy Of A Kong Plugin

Every Kong plugin has two main files:

| File | Purpose |
| --- | --- |
| `handler.lua` | The plugin behavior: what Kong does during a request/response |
| `schema.lua` | The plugin configuration schema: what settings are allowed |

### `handler.lua`

This file contains the actual logic.

Common Kong phases:

| Phase | When It Runs | Common Use |
| --- | --- | --- |
| `rewrite` | Very early, before routing finishes | URI changes, early decisions |
| `access` | Before proxying to upstream | Auth, validation, request headers |
| `header_filter` | When response headers come back | Add/modify response headers |
| `body_filter` | While response body streams back | Body transformations |
| `log` | After response is sent | Logging, metrics, audit events |

Example shape:

```lua
local MyPlugin = {
  VERSION = "0.1.0",
  PRIORITY = 900,
}

function MyPlugin:access(conf)
  kong.service.request.set_header("X-Example", conf.example_value)
end

return MyPlugin
```

### `schema.lua`

This file tells Kong what config your plugin accepts.

Example shape:

```lua
return {
  name = "my-plugin",
  fields = {
    { config = {
        type = "record",
        fields = {
          { example_value = {
              type = "string",
              default = "hello",
            },
          },
        },
      },
    },
  },
}
```

### `.rockspec`

The rockspec tells LuaRocks which Lua files belong in the plugin package.

Example shape:

```lua
package = "kong-plugin-my-plugin"
version = "0.1.0-1"

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.my-plugin.handler"] = "kong/plugins/my-plugin/handler.lua",
    ["kong.plugins.my-plugin.schema"] = "kong/plugins/my-plugin/schema.lua",
  },
}
```

🔴 The rockspec filename must match the package and version:

```text
kong-plugin-my-plugin-0.1.0-1.rockspec
```

If the filename and package do not match, LuaRocks will fail.

## 🚀 How Kong Starts Locally

Docker Compose starts two services:

| Service | Purpose |
| --- | --- |
| 🟦 `kong` | Kong Gateway `3.4.2` with the custom plugin installer |
| 🟩 `echo` | A tiny local upstream used by tests |

The echo service means tests do not need the internet. Kong proxies to:

```yaml
url: http://echo:8080
```

The Kong container mounts:

```yaml
volumes:
  - ./build/out:/rocks:ro
  - ./kong/kong.yml:/kong/declarative/kong.yml:ro
```

So inside the Kong container:

| Host Path | Container Path | Purpose |
| --- | --- | --- |
| `./build/out` | `/rocks` | Plugin `.rock` files |
| `./kong/kong.yml` | `/kong/declarative/kong.yml` | DB-less Kong config |

Before Kong starts, this script runs:

```text
docker/kong-install-rocks.sh
```

It does this:

```sh
luarocks install --force /rocks/*.rock
```

Then it hands control back to Kong's normal Docker entrypoint.

## ⚙️ How Kong Knows About The Plugins

Kong needs two things:

1. The plugin Lua files must be installed.
2. The plugin names must be listed in `KONG_PLUGINS`.

In `docker-compose.yml`:

```yaml
KONG_PLUGINS: bundled,request-profiler,json-field-guard,canary-header-router
```

Meaning:

- `bundled` keeps Kong's built-in plugins available.
- The other names are your custom plugins.

🔴 If you add a plugin but forget to add it to `KONG_PLUGINS`, Kong will not load it.

## 🧾 How `kong/kong.yml` Works

This repo uses Kong in DB-less mode:

```yaml
KONG_DATABASE: "off"
KONG_DECLARATIVE_CONFIG: /kong/declarative/kong.yml
```

That means there is no Postgres database. Kong reads all routes, services, and plugin configs from:

```text
kong/kong.yml
```

The current config has:

```yaml
services:
  - name: local-echo
    url: http://echo:8080
```

Routes:

| Route | Path | Purpose |
| --- | --- | --- |
| `anything` | `/anything` | General test route |
| `guarded-json` | `/guarded` | JSON validation route |

Plugin placement:

| Plugin | Placement | Meaning |
| --- | --- | --- |
| `request-profiler` | Global | Runs on all matching requests |
| `canary-header-router` | Global | Runs on all matching requests |
| `json-field-guard` | Route-level | Only runs on `/guarded` route |

## 🧪 Included Example Plugins

These are sample plugins to prove the build/install/runtime loop.

### 🟢 `request-profiler`

What it does:

- Adds or preserves an `X-Request-Id`.
- Sends the request ID upstream.
- Adds `X-Kong-Elapsed` to the response.
- Logs a small request summary.

Useful for:

- Correlation IDs
- Timing checks
- Basic observability

### 🟣 `json-field-guard`

What it does:

- Only allows JSON payloads.
- Requires fields like `customer_id` and `action`.
- Rejects forbidden keys like `password`, `ssn`, and `credit_card`.
- Adds `X-Json-Guard: passed` when the request is valid.

Useful for:

- Request validation
- Guardrails before traffic reaches upstream services
- Blocking risky payload fields

### 🟠 `canary-header-router`

What it does:

- Assigns requests to `stable` or `canary`.
- Supports forced override with `X-Canary-Override`.
- Sends `X-Release-Track` upstream.
- Adds decision headers to the response.

Useful for:

- Canary rollout experiments
- Sticky release-track decisions
- Testing header-based routing logic

## 🧪 Automated Postman Tests

The easiest verification command is:

```powershell
.\postman\run-collection.ps1
```

The script does this automatically:

1. 📦 Runs `make package` if `make` is installed.
2. 🔎 Confirms `.rock` files exist in `build/out`.
3. 🚀 Starts Docker Compose.
4. ⏳ Waits for Kong to become ready.
5. 🧪 Runs the Postman collection with Newman.
6. 📄 Writes results to `build/postman/newman-results.json`.
7. 🧹 Stops Compose unless you pass `-KeepRunning`.

Expected summary:

```text
Postman summary: requests=10/10, assertions=27/27, failures=0
```

Useful options:

```powershell
.\postman\run-collection.ps1 -SkipPackage
.\postman\run-collection.ps1 -KeepRunning
.\postman\run-collection.ps1 -UseDockerNewman
.\postman\run-collection.ps1 -ProxyPort 18000 -AdminPort 18001 -StatusPort 18100
```

## 🧭 Manual Checks

Start Kong:

```sh
docker compose up --build
```

Check status:

```sh
curl -i http://localhost:8100/status
```

Check Kong version:

```sh
curl -i http://localhost:8001/
```

Check request profiling:

```sh
curl -i http://localhost:8000/anything/get
```

Force canary:

```sh
curl -i -H "X-Canary-Override: canary" http://localhost:8000/anything/headers
```

Send valid guarded JSON:

```sh
curl -i -X POST http://localhost:8000/guarded/post \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"cust-123","action":"signup"}'
```

Send rejected guarded JSON:

```sh
curl -i -X POST http://localhost:8000/guarded/post \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"cust-123","action":"signup","password":"secret"}'
```

## 🏢 How To Replicate This For Work

Use this checklist when replacing the example plugins with work plugins.

### 1. Create A Plugin Folder

Create:

```text
custom-plugins/my-work-plugin/
```

Inside it, use this structure:

```text
custom-plugins/my-work-plugin/
├── kong-plugin-my-work-plugin-0.1.0-1.rockspec
└── kong/
    └── plugins/
        └── my-work-plugin/
            ├── handler.lua
            └── schema.lua
```

The folder name, Kong plugin name, and Lua module path should match:

```text
my-work-plugin
kong.plugins.my-work-plugin.handler
kong.plugins.my-work-plugin.schema
```

### 2. Update The Rockspec

Use this pattern:

```lua
package = "kong-plugin-my-work-plugin"
version = "0.1.0-1"

source = {
  url = ".",
}

description = {
  summary = "My work Kong plugin.",
  license = "Proprietary",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.my-work-plugin.handler"] = "kong/plugins/my-work-plugin/handler.lua",
    ["kong.plugins.my-work-plugin.schema"] = "kong/plugins/my-work-plugin/schema.lua",
  },
}
```

### 3. Add The Plugin To `KONG_PLUGINS`

In `docker-compose.yml`, change:

```yaml
KONG_PLUGINS: bundled,request-profiler,json-field-guard,canary-header-router
```

To something like:

```yaml
KONG_PLUGINS: bundled,my-work-plugin
```

Or, if you have several:

```yaml
KONG_PLUGINS: bundled,my-auth-plugin,my-transform-plugin,my-logging-plugin
```

### 4. Configure The Plugin In `kong/kong.yml`

Global plugin example:

```yaml
plugins:
  - name: my-work-plugin
    config:
      enabled_feature: true
```

Route-level plugin example:

```yaml
services:
  - name: local-echo
    url: http://echo:8080
    routes:
      - name: my-route
        paths:
          - /my-route
        plugins:
          - name: my-work-plugin
            config:
              enabled_feature: true
```

Rule of thumb:

| Placement | Use When |
| --- | --- |
| Global plugin | It should run for every request |
| Service plugin | It should run for every route under one upstream service |
| Route plugin | It should run only for specific paths/methods |
| Consumer plugin | It should run only for specific authenticated consumers |

### 5. Package And Run

```sh
make package
docker compose up --build
```

### 6. Update Postman Tests

Edit:

```text
postman/Kong_3_4_2_Custom_Plugins.postman_collection.json
```

Add tests that prove your work plugin actually works.

Good tests usually check:

- 🟢 Expected status code
- 🔵 Expected request headers sent upstream
- 🟣 Expected response headers
- 🟠 Expected blocked/rejected requests
- 🔴 Expected error shape when input is invalid

Then run:

```powershell
.\postman\run-collection.ps1
```

## ✅ Work Plugin Replacement Checklist

Use this before sharing your work version:

- 🟢 Plugin folder exists under `custom-plugins/`.
- 🟢 Plugin has `handler.lua`.
- 🟢 Plugin has `schema.lua`.
- 🟢 Plugin has a matching `kong-plugin-<name>-<version>.rockspec`.
- 🟢 `make package` creates a `.rock` file in `build/out`.
- 🟢 `docker-compose.yml` includes the plugin name in `KONG_PLUGINS`.
- 🟢 `kong/kong.yml` configures the plugin where it should run.
- 🟢 `docker compose up --build` starts successfully.
- 🟢 Postman/Newman tests pass.
- 🔴 No secrets, tokens, private URLs, or customer data are committed.

## 🛠 Troubleshooting

### 🔴 Kong exits and says no `.rock` files were found

Cause:

```text
build/out/ is empty
```

Fix:

```sh
make package
docker compose up --build
```

### 🔴 Kong says the plugin is enabled but not installed

Usually one of these is wrong:

- The `.rock` file was not created.
- The `.rock` file is not in `build/out`.
- The rockspec module path is wrong.
- `handler.lua` or `schema.lua` is missing from the rockspec.

Check:

```sh
ls build/out
```

### 🔴 Kong says the plugin is not enabled

Add it to `KONG_PLUGINS` in `docker-compose.yml`:

```yaml
KONG_PLUGINS: bundled,my-work-plugin
```

### 🔴 LuaRocks complains about the rockspec name

The rockspec filename must match:

```lua
package = "kong-plugin-my-work-plugin"
version = "0.1.0-1"
```

Correct filename:

```text
kong-plugin-my-work-plugin-0.1.0-1.rockspec
```

### 🟡 Port `8000` is already in use

The Postman runner handles this automatically.

For manual Compose runs, set a different port:

```powershell
$env:KONG_PROXY_PORT = "18000"
docker compose up --build
```

Then call:

```text
http://localhost:18000
```

### 🟡 `make` is missing on Windows

Install one of these:

- Git Bash with `make`
- Chocolatey `make`
- WSL
- A dev container or Linux build agent

The runtime is Docker-based, but packaging expects a Make-compatible shell.

### 🟡 Newman is missing

The runner can use Dockerized Newman:

```powershell
.\postman\run-collection.ps1 -UseDockerNewman
```

Or install Newman locally:

```sh
npm install -g newman
```

## 🧹 Cleanup

Stop containers:

```sh
docker compose down
```

Remove Pongo/build outputs:

```sh
make expunge
```

Generated folders:

| Folder | Safe To Delete? | Why |
| --- | --- | --- |
| `.venv/` | ✅ Yes | Recreated by `make package` |
| `build/out/` | ✅ Yes | Recreated by `make package` |
| `build/postman/` | ✅ Yes | Recreated by the Postman runner |

## 🧷 Final Mental Model

Think of the repo like this:

```text
custom-plugins/       = plugin source code
Makefile              = turns plugin source into .rock packages
build/out/            = packaged plugin artifacts
docker-compose.yml    = starts Kong and mounts the artifacts
kong/kong.yml         = tells Kong where routes/services/plugins are
postman/              = proves the setup works end to end
```

For work, keep the machinery and swap the plugin content.

🟢 Same packaging pattern.  
🟢 Same Docker install pattern.  
🟢 Same DB-less Kong config pattern.  
🟢 Different real plugins and different Postman assertions.
