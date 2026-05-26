# 🟦 Kong Plugins Builder

![Kong](https://img.shields.io/badge/Kong%20Gateway-3.4.2-00A3E0)
![Docker Compose](https://img.shields.io/badge/Docker%20Compose-required-2496ED)
![LuaRocks](https://img.shields.io/badge/plugins-.rock%20files-2ECC71)
![Postman](https://img.shields.io/badge/Postman%20tests-automated-FF6C37)

This repo is a local, containerized Kong plugin lab.

Overview: put Lua Kong plugins into `custom-plugins/`, run `docker compose up --build`, and the repo builds those plugins into LuaRocks `.rock` files before Kong starts. Kong Gateway `3.4.2` then installs those `.rock` files, loads the enabled plugins, and exposes everything locally.

The sample plugins are only examples. For another project, you will replace them with your real plugins but keep the same packaging and runtime pattern.

If you are copying this repo as a template, start with [`TEMPLATE_USAGE.md`](TEMPLATE_USAGE.md). For step-by-step testing, use [`TEST_RUNBOOK.md`](TEST_RUNBOOK.md). For the deeper implementation details, read [`TECHNICAL_README.md`](TECHNICAL_README.md).

## 🟢 Quick Start

One command packages plugins, starts Keycloak, starts Kong, and installs the generated rocks:

```sh
docker compose up --build
```

What happens:

- 📦 `plugin-packager` builds every plugin under `custom-plugins/`.
- 🪨 `.rock` files are written to `build/out/`.
- 🔐 Keycloak starts by default for SAML testing.
- 🦍 Kong starts and installs the generated rocks.
- 🧪 `kong/kong.yml` decides which plugins run on which routes.

If the stack is already running and you changed plugin source, recreate the containers so Kong installs the fresh rocks:

```sh
docker compose up --build --force-recreate
```

Template checklist:

```text
Add source in custom-plugins/  -> built automatically
Add name to KONG_PLUGINS      -> Kong can load it
Add config to kong/kong.yml   -> Kong actually runs it
```

Run the automated Postman/Newman tests:

```sh
docker compose run --rm newman
```

Or run the full package/start/test/stop flow through Maven:

```sh
mvn verify
```

Or, if you only want Bash and `curl`, start Kong and run:

```sh
bash tests/bash/run-curl-tests.sh
```

Maven automation:

| Command | What It Does |
| --- | --- |
| `mvn package` | Packages plugin rocks through `docker compose run --rm --build plugin-packager` |
| `mvn verify` | Packages rocks, starts Kong, Keycloak, runs Compose Newman tests and the SAML browser-flow check, then stops Compose |
| `mvn -Ddocker.compose.skip=true verify` | Runs Maven without Docker Compose automation |

Local Keycloak SAML IdP:

```sh
docker compose up -d keycloak
```

Plain `docker compose up --build` starts Keycloak too.

Keycloak runs at `http://localhost:18080` and imports the `kong-plugin-lab` realm from `keycloak/realm-export.json`.

If Keycloak was already running before you changed the realm export, recreate the `keycloak` container so the new `/auth` ACS URL is imported.

Useful local URLs:

| Purpose | URL |
| --- | --- |
| Kong proxy | `http://localhost:8000` |
| Kong Admin API | `http://localhost:8001` |
| Kong status API | `http://localhost:8100/status` |
| Keycloak admin console | `http://localhost:18080/admin` |
| Keycloak SAML metadata | `http://localhost:18080/realms/kong-plugin-lab/protocol/saml/descriptor` |
| SAML protected demo route | `http://localhost:8000/saml-demo` |
| SAML ACS callback route | `http://localhost:8000/auth` |

If port `8000` is already busy, the Postman runner automatically chooses a free port for that test run.

Optional local overrides live in `.env.example`. Copy it to `.env` only if you want to change ports, Keycloak admin credentials, or native build settings.

## 🧠 Big Picture

The repo has two separate jobs:

| Job | Tool | What It Does |
| --- | --- | --- |
| 📦 Build plugins | `plugin-packager` Compose job | Converts Lua plugin folders into `.rock` files inside a Kong `3.4.2` container |
| 🚀 Run Kong locally | `docker compose up --build` | Runs the packager first, then starts Kong `3.4.2` and installs those `.rock` files |

Important version note:

```make
PONGO_VERSION := 2.12.0
KONG_VERSION := 3.4.2
```

Those values are used by the Makefile/Pongo packaging flow. The Docker Compose packaging flow and the actual local Kong runtime both use Kong `3.4.2`:

```yaml
image: local/kong-plugins-builder:3.4.2
```

So these versions are now aligned:

- 🟨 `KONG_VERSION := 3.4.2` in the Makefile controls the Pongo build environment.
- 🟦 `kong:3.4.2` in Docker controls the local Kong Gateway runtime.

## 📁 Repo Layout

```text
.
├── custom-plugins/
│   ├── request-profiler/
│   ├── json-field-guard/
│   ├── canary-header-router/
│   └── saml-jwe-auth/
├── build/out/
├── docker/
│   ├── kong.Dockerfile
│   ├── kong-install-rocks.sh
│   ├── echo-server.Dockerfile
│   └── echo-server.py
├── kong/
│   └── kong.yml
├── tests/
│   ├── postman/
│   ├── insomnia/
│   └── bash/
├── docker-compose.yml
├── Makefile
└── README.md
```

What each folder means:

| Path | Meaning |
| --- | --- |
| 🟢 `custom-plugins/` | The actual Lua Kong plugin source lives here |
| 🟡 `build/out/` | Generated `.rock` files land here after packaging |
| 🔵 `docker/` | Docker image files and helper scripts |
| 🔐 `keycloak/` | Local Keycloak realm export for SAML IdP testing |
| 🟣 `kong/kong.yml` | Kong DB-less config: services, routes, and enabled plugin instances |
| 🟠 `tests/` | Automated smoke tests in Postman, Insomnia, and Bash/curl formats |
| ⚪ `src/` | Existing Maven archetype files; not used by the Kong runtime |
| 🌈 `.env.example` | Optional local environment overrides for ports and credentials |
| 🧩 `TEMPLATE_USAGE.md` | Copy-from-template checklist and plugin replacement guide |
| 🧪 `TEST_RUNBOOK.md` | Step-by-step local verification runbook |

## 🔁 Full Flow

Here is the whole system from left to right:

```text
Lua plugin source
      ↓
custom-plugins/<plugin-name>/
      ↓
docker compose up --build
      ↓
plugin-packager job
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
Smoke tests confirm everything works
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

The Docker Compose packager finds every folder under `custom-plugins/` that contains a `.rockspec` file. The Makefile uses the same folder convention:

```make
PLUGIN_DIRS := $(wildcard custom-plugins/*)
```

The normal template command packages them inside a Kong `3.4.2` container before Kong starts:

```sh
docker compose up --build
```

You can still run the packager by itself when you only want to rebuild rocks:

```sh
docker compose run --rm --build plugin-packager
```

That creates:

```text
build/out/kong-plugin-request-profiler-0.1.0-1.all.rock
build/out/kong-plugin-json-field-guard-0.1.0-1.all.rock
build/out/kong-plugin-canary-header-router-0.1.0-1.all.rock
build/out/kong-plugin-saml-jwe-auth-0.1.0-1.all.rock
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

## Native Lua FFI And C-Backed Plugins

This project supports custom Kong plugins that load native Linux shared libraries through LuaJIT FFI or Lua C modules.

Use this layout for proprietary native artifacts:

```text
custom-plugins/my-plugin/
|-- kong-plugin-my-plugin-0.1.0-1.rockspec
|-- kong/
|   `-- plugins/
|       `-- my-plugin/
|           |-- handler.lua
|           `-- schema.lua
`-- native/
    `-- libmy_work_plugin.so
```

The packaging flow stages `custom-plugins/<plugin>/native/**/*.so*` into:

```text
build/out/native/<plugin>/
```

When Kong starts, `docker/kong-install-rocks.sh` copies those Linux `.so` files into:

```text
/usr/local/lib/kong-plugins
```

The Compose runtime also sets:

```yaml
LD_LIBRARY_PATH: /usr/local/lib/kong-plugins
KONG_LUA_PACKAGE_CPATH: "/usr/local/lib/kong-plugins/?.so;/usr/local/lib/kong-plugins/lib?.so;/usr/local/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/?/init.so;;"
KONG_NGINX_MAIN_ENV: LD_LIBRARY_PATH
```

That gives two supported native loading patterns:

```lua
local ffi = require "ffi"
ffi.cdef [[
  int my_native_function(const char *input);
]]

local native = ffi.load("my_work_plugin")
```

and Lua C modules:

```lua
local native = require "my_native_module"
```

If your proprietary plugin is delivered as a prebuilt `.rock`, put it in either:

```text
custom-plugins/my-plugin/rocks/
custom-plugins/my-plugin/dist/
```

The package target copies those rocks into `build/out/` without rebuilding them.

Native compatibility rules:

- Use Linux `.so` files, not Windows `.dll` or macOS `.dylib` files.
- The `.so` architecture must match the Kong container architecture, for example `linux/amd64`.
- Build against a libc compatible with the Kong image.
- If the rock must compile C during `docker compose build`, set `INSTALL_NATIVE_BUILD_DEPS=true` before building.

## 🚀 How Kong Starts Locally

Docker Compose starts three main services:

| Service | Purpose |
| --- | --- |
| `kong` | Kong Gateway `3.4.2` with the custom plugin installer |
| `echo` | A tiny local upstream used by tests |
| `keycloak` | Local SAML IdP used by the SAML/JWE demo flow |

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
KONG_PLUGINS: bundled,request-profiler,json-field-guard,canary-header-router,saml-jwe-auth
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

### `saml-jwe-auth`

What it does:

- Starts browser SAML login when a request has no valid JWE session.
- Exposes a configurable ACS path, for example `/auth`.
- Validates signed SAML Response and signed Assertion with libxml2, xmlsec1, and OpenSSL.
- Extracts configured SAML attributes into an encrypted JWE session.
- Sends configured trusted identity headers upstream after the JWE is valid.

This plugin is packaged, enabled, and attached to the local SAML demo service in `kong/kong.yml`. The protected route is `/saml-demo`; the ACS callback route is `/auth`.

## 🧪 Automated Smoke Tests

The easiest verification command is still the Postman/Newman runner:

```powershell
.\tests\postman\run-collection.ps1
```

The script does this automatically:

1. 📦 Runs `docker compose run --rm --build plugin-packager`.
2. 🔎 Confirms `.rock` files exist in `build/out`.
3. 🚀 Starts Docker Compose.
4. ⏳ Waits for Kong to become ready.
5. 🧪 Runs the Postman collection with the Compose `newman` service.
6. 📄 Writes results to `build/postman/newman-results.json`.
7. 🧹 Stops Compose unless you pass `-KeepRunning`.

Expected summary:

```text
Postman summary: requests=11/11, assertions=30/30, failures=0
```

Useful options:

```powershell
.\tests\postman\run-collection.ps1 -SkipPackage
.\tests\postman\run-collection.ps1 -KeepRunning
.\tests\postman\run-collection.ps1 -ProxyPort 18000 -AdminPort 18001 -StatusPort 18100
```

The same requests are also available without Postman:

| Format | Location | How to use |
| --- | --- | --- |
| Insomnia | `tests/insomnia/Kong_3_4_2_Custom_Plugins.insomnia.json` | Import into Insomnia and run the collection |
| Bash/curl | `tests/bash/run-curl-tests.sh` | Run `bash tests/bash/run-curl-tests.sh` after Kong is up |

## 🔐 Local Keycloak SAML IdP

This repo includes a Keycloak service for local SAML IdP testing. It is deliberately separate from the Kong plugins.

```sh
docker compose up -d keycloak
```

Plain `docker compose up --build` starts Keycloak with Kong and the echo upstream.

Keycloak details:

| Item | Value |
| --- | --- |
| Admin console | `http://localhost:18080/admin` |
| Local admin username | `admin` |
| Local admin password | `admin` |
| Realm | `kong-plugin-lab` |
| SAML client / SP entity ID | `kong-saml-auth-service` |
| Test user | `alice` / `alice-password` |
| Realm metadata | `http://localhost:18080/realms/kong-plugin-lab/protocol/saml/descriptor` |

The full working SAML configuration is documented in [`keycloak/README.md`](keycloak/README.md), including every Keycloak realm/client attribute, mapper, test-user value, and matching Kong plugin setting.

The SAML client is configured for both signed response documents and signed assertions:

| Security Setting | Realm Export Attribute | Value |
| --- | --- | --- |
| Signed SAML Response | `saml.server.signature` | `true` |
| Signed SAML Assertion | `saml.assertion.signature` | `true` |
| Signature algorithm | `saml.signature.algorithm` | `RSA_SHA256` |
| One-time-use condition | `saml.onetimeuse.condition` | `true` |

The intended local plugin flow is:

```text
Keycloak IdP
      -> signed SAMLResponse and signed Assertion
Kong saml-jwe-auth plugin ACS path, for example /auth
      -> encrypted JWE session cookie
Kong saml-jwe-auth plugin checks the encrypted JWE on later requests
      -> trusted identity headers
upstream API
```

The plugin keeps XML signature validation and JWE cryptography in a native C bridge backed by libxml2, xmlsec1, and OpenSSL. It validates signed response, signed assertion, issuer, audience, destination, recipient, timestamps, replay protection, and matching `InResponseTo`.

The default `kong/kong.yml` attaches `saml-jwe-auth` only to the SAML demo service. The existing `/anything` and `/guarded` smoke-test routes do not require browser SSO.

Local SAML demo routes:

| Route | Purpose |
| --- | --- |
| `http://localhost:8000/saml-demo` | Protected route that starts SP-initiated SAML login when no JWE session exists |
| `http://localhost:8000/auth` | Assertion Consumer Service callback used by Keycloak |

Browser journey:

1. Open `http://localhost:8000/saml-demo`.
2. Kong redirects to Keycloak.
3. Log in with `alice` / `alice-password`.
4. Keycloak posts a signed `SAMLResponse` and `RelayState` to `http://localhost:8000/auth`.
5. Kong validates the signed Response and signed Assertion, sets the `kong_saml_session` JWE cookie, then redirects back to `/saml-demo`.
6. The echo upstream response should show `X-Authenticated-User: alice` and `X-Authenticated-Email: alice@example.test`.

See `keycloak/README.md` for the exact imported realm settings and reset commands.

Run the Keycloak SAML Postman/Newman checks with:

```powershell
.\tests\postman\run-keycloak-saml-collection.ps1
```

Run the full SAML login journey check inside Docker Compose with:

```powershell
docker compose run --rm --entrypoint node newman /etc/newman/saml-browser-flow-check.js
```

Inspect the SAML response from the Kong plugin logs:

```powershell
docker compose logs -f kong | Select-String "saml-jwe-auth debug"
```

The local demo config logs the outgoing `SAMLRequest`, AuthnRequest XML, received `SAMLResponse`, decoded SAML XML, validation result, subject, and mapped attributes. Disable `debug_log_saml_request`, `debug_log_saml_response`, and `debug_capture_dir` in `kong/kong.yml` when you do not want SAML values, signed SAML XML, and user attributes written to logs or capture files.

For the full copyable `SAMLResponse` value, use the capture files in `saml-plugin-outputs`:

```powershell
$latest = Get-ChildItem .\saml-plugin-outputs\*_saml-response.b64 | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content -Raw $latest.FullName
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

## 🏢 How To Reuse This Template

Use this checklist when replacing the example plugins with custom plugins.

### 1. Create A Plugin Folder

Create:

```text
custom-plugins/my-plugin/
```

Inside it, use this structure:

```text
custom-plugins/my-plugin/
├── kong-plugin-my-plugin-0.1.0-1.rockspec
└── kong/
    └── plugins/
        └── my-plugin/
            ├── handler.lua
            └── schema.lua
```

The folder name, Kong plugin name, and Lua module path should match:

```text
my-plugin
kong.plugins.my-plugin.handler
kong.plugins.my-plugin.schema
```

### 2. Update The Rockspec

Use this pattern:

```lua
package = "kong-plugin-my-plugin"
version = "0.1.0-1"

source = {
  url = ".",
}

description = {
  summary = "Example Kong plugin.",
  license = "Proprietary",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.my-plugin.handler"] = "kong/plugins/my-plugin/handler.lua",
    ["kong.plugins.my-plugin.schema"] = "kong/plugins/my-plugin/schema.lua",
  },
}
```

### 3. Add The Plugin To `KONG_PLUGINS`

In `docker-compose.yml`, change:

```yaml
KONG_PLUGINS: bundled,request-profiler,json-field-guard,canary-header-router,saml-jwe-auth
```

To something like:

```yaml
KONG_PLUGINS: bundled,my-plugin
```

Or, if you have several:

```yaml
KONG_PLUGINS: bundled,my-auth-plugin,my-transform-plugin,my-logging-plugin
```

### 4. Configure The Plugin In `kong/kong.yml`

Global plugin example:

```yaml
plugins:
  - name: my-plugin
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
          - name: my-plugin
            config:
              enabled_feature: true
```

Placement guide:

| Placement | Use When |
| --- | --- |
| Global plugin | It should run for every request |
| Service plugin | It should run for every route under one upstream service |
| Route plugin | It should run only for specific paths/methods |
| Consumer plugin | It should run only for specific authenticated consumers |

### 5. Package And Run

```sh
docker compose up --build
```

That one command runs the `plugin-packager` job first, writes fresh rocks into `build/out/`, then starts Kong.

### 6. Update Smoke Tests

Edit:

```text
tests/postman/Kong_3_4_2_Custom_Plugins.postman_collection.json
tests/insomnia/Kong_3_4_2_Custom_Plugins.insomnia.json
tests/bash/run-curl-tests.sh
```

Add or update tests that prove your custom plugin actually works.

Good tests usually check:

- 🟢 Expected status code
- 🔵 Expected request headers sent upstream
- 🟣 Expected response headers
- 🟠 Expected blocked/rejected requests
- 🔴 Expected error shape when input is invalid

Then run:

```powershell
.\tests\postman\run-collection.ps1
```

## ✅ Custom Plugin Checklist

Use this before sharing your custom plugin project:

- 🟢 Plugin folder exists under `custom-plugins/`.
- 🟢 Plugin has `handler.lua`.
- 🟢 Plugin has `schema.lua`.
- 🟢 Plugin has a matching `kong-plugin-<name>-<version>.rockspec`.
- 🟢 `docker compose up --build` runs the packager and creates `.rock` files in `build/out`.
- 🟢 `docker-compose.yml` includes the plugin name in `KONG_PLUGINS`.
- 🟢 `kong/kong.yml` configures the plugin where it should run.
- 🟢 `docker compose up --build` starts successfully.
- 🟢 Smoke tests pass.
- 🔴 No secrets, tokens, private URLs, or customer data are committed.

## 🛠 Troubleshooting

### 🔴 Kong exits and says no `.rock` files were found

Cause:

```text
build/out/ is empty
```

Fix:

```sh
docker compose up --build --force-recreate
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
KONG_PLUGINS: bundled,my-plugin
```

### 🔴 LuaRocks complains about the rockspec name

The rockspec filename must match:

```lua
package = "kong-plugin-my-plugin"
version = "0.1.0-1"
```

Correct filename:

```text
kong-plugin-my-plugin-0.1.0-1.rockspec
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

The legacy Makefile target expects a Make-compatible shell. The Docker Compose packager and `mvn package` do not require local `make`.

### 🟡 Newman is missing

Newman now runs through Docker Compose:

```powershell
docker compose run --rm newman
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
| `.venv/` | ✅ Yes | Recreated by the legacy Makefile/Pongo flow |
| `build/out/` | ✅ Yes | Recreated by packaging |
| `build/postman/` | ✅ Yes | Recreated by the Postman runner |

## 🧷 Architecture Summary

Think of the repo like this:

```text
custom-plugins/       = plugin source code
Makefile              = turns plugin source into .rock packages
build/out/            = packaged plugin artifacts
docker-compose.yml    = starts Kong and mounts the artifacts
kong/kong.yml         = tells Kong where routes/services/plugins are
tests/                = proves the setup works end to end
```

For another project, keep the machinery and swap the plugin content.

🟢 Same packaging pattern.  
🟢 Same Docker install pattern.  
🟢 Same DB-less Kong config pattern.  
🟢 Different real plugins and different smoke-test assertions.
