# Technical README: Kong Plugin Build, Install, Enable, and Configure Flow

This document explains the mechanics of this repo in detail. It is intended for developers who need to reproduce the same pattern with different Kong plugins.

The short version:

```text
custom-plugins/<plugin>/        plugin source
custom-plugins/<plugin>/*.rockspec
        |
        | docker compose up --build
        v
plugin-packager service          one-shot packaging job
        |
        v
build/out/*.rock                packaged LuaRocks artifacts
        |
        | Kong depends on successful packaging
        v
Kong 3.4.2 container startup
        |
        | docker/kong-install-rocks.sh
        v
luarocks install --force /rocks/*.rock
        |
        | KONG_PLUGINS + kong/kong.yml
        v
plugins loaded and configured in Kong
```

## 1. Versions Used By This Repo

There are two version concerns in this project.

### 1.1 Packaging versions

The Makefile uses Pongo to build and pack the plugins:

```make
PONGO_VERSION := 2.12.0
KONG_VERSION := 3.4.2
```

These values are used by the legacy `make package` workflow.

### 1.2 Runtime Kong version

The local Kong instance is Kong Gateway `3.4.2`:

```dockerfile
FROM kong:3.4.2
```

This is the Kong version that actually starts, installs the rocks, loads the plugins, and handles requests.

Important distinction:

| Area | Version |
| --- | --- |
| Plugin packaging with Pongo | `PONGO_VERSION := 2.12.0` |
| Pongo Kong build environment | `KONG_VERSION := 3.4.2` |
| Local runtime gateway | `kong:3.4.2` |

The Pongo build environment and the local runtime are intentionally aligned to Kong `3.4.2`.

## 2. Plugin Source Layout

Each plugin under `custom-plugins/` is a self-contained LuaRocks project.

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

The important naming relationship is:

```text
Plugin name:        request-profiler
Lua handler module: kong.plugins.request-profiler.handler
Lua schema module:  kong.plugins.request-profiler.schema
Rockspec package:   kong-plugin-request-profiler
Rockspec file:      kong-plugin-request-profiler-0.1.0-1.rockspec
```

These names must stay consistent.

## 3. Kong Plugin Files

Every plugin in this repo has these files:

```text
handler.lua
schema.lua
kong-plugin-<plugin-name>-<version>.rockspec
```

### 3.1 `handler.lua`

`handler.lua` contains the plugin behavior.

A Kong plugin handler normally exports a Lua table:

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

Key fields:

| Field | Meaning |
| --- | --- |
| `VERSION` | Your plugin version |
| `PRIORITY` | Determines order relative to other plugins in the same phase |

Higher `PRIORITY` values generally run earlier in a given phase.

Common phases:

| Phase | Runs When | Typical Use |
| --- | --- | --- |
| `init_worker` | Worker starts | Timers, worker setup |
| `certificate` | TLS certificate selection | Dynamic cert logic |
| `rewrite` | Early request phase | URI rewriting, early routing changes |
| `access` | Before upstream proxy | Auth, validation, request mutation |
| `header_filter` | Response headers received | Response header mutation |
| `body_filter` | Response body streaming | Response body mutation |
| `log` | Request finished | Logging, audit, metrics |

The sample plugins use:

| Plugin | Phases Used |
| --- | --- |
| `request-profiler` | `access`, `header_filter`, `log` |
| `json-field-guard` | `access` |
| `canary-header-router` | `access`, `header_filter` |

### 3.2 `schema.lua`

`schema.lua` defines the plugin config Kong will accept.

Example shape:

```lua
local typedefs = require "kong.db.schema.typedefs"

return {
  name = "my-plugin",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { example_value = {
              type = "string",
              default = "hello",
              len_min = 1,
            },
          },
        },
      },
    },
  },
}
```

Important pieces:

| Schema Part | Purpose |
| --- | --- |
| `name` | Must match the Kong plugin name |
| `consumer = typedefs.no_consumer` | Disallows consumer-scoped config |
| `protocols = typedefs.protocols_http` | Restricts the plugin to HTTP protocols |
| `config` | Defines plugin-specific settings |

Common validation options:

| Option | Meaning |
| --- | --- |
| `type = "string"` | String value |
| `type = "boolean"` | Boolean value |
| `type = "integer"` | Integer value |
| `type = "array"` | List value |
| `default = ...` | Default if omitted |
| `len_min = 1` | Minimum string length |
| `between = { min, max }` | Numeric bounds |
| `one_of = { ... }` | Allowed values |
| `elements = { ... }` | Schema for array items |

Kong validates `kong/kong.yml` against these schemas at startup.

If your schema is wrong, Kong can fail before it starts proxying traffic.

### 3.3 The `.rockspec`

The rockspec tells LuaRocks how to package the plugin.

Example:

```lua
package = "kong-plugin-my-plugin"
version = "0.1.0-1"

source = {
  url = ".",
}

description = {
  summary = "My Kong plugin.",
  license = "MIT",
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

The `modules` table is critical.

It maps Lua module names to files:

```lua
["kong.plugins.my-plugin.handler"] = "kong/plugins/my-plugin/handler.lua"
```

That means after installation, Kong can do the equivalent of:

```lua
require "kong.plugins.my-plugin.handler"
require "kong.plugins.my-plugin.schema"
```

Rockspec naming rule:

```text
package = "kong-plugin-my-plugin"
version = "0.1.0-1"
```

Requires this filename:

```text
kong-plugin-my-plugin-0.1.0-1.rockspec
```

If the filename does not match the `package` and `version`, LuaRocks will fail.

## 4. Build Flow: Docker Compose Packager

The primary template command is:

```sh
docker compose up --build
```

Compose runs `plugin-packager` as a short-lived one-shot service before Kong starts. The service is based on Kong `3.4.2` and executes:

```text
docker/package-plugins.sh
```

That script uses LuaRocks from the Kong image to build each plugin into `build/out`. You can still run only the packaging job with `docker compose run --rm --build plugin-packager`.

The Makefile remains available as a Pongo-based alternative and has four main targets:

| Target | Purpose |
| --- | --- |
| `build-venv` | Downloads Pongo and prepares `.venv/env` |
| `package` | Builds and packs every plugin into `.rock` files |
| `test` | Runs Pongo tests for each plugin directory |
| `expunge` | Removes Pongo/build artifacts |

### 4.1 `build-venv`

This target creates local Pongo tooling:

```make
build-venv:
	@mkdir -p .venv/bin
	@git clone https://github.com/Kong/kong-pongo.git --depth 1 --branch $(PONGO_VERSION) .venv/pongo || true
	@ln -sf $$(pwd)/.venv/pongo/pongo.sh $$(pwd)/.venv/bin/pongo
	@echo "export PATH=$$(pwd)/.venv/bin:$$PATH" > .venv/env
	@echo "export KONG_VERSION=$(KONG_VERSION)" >> .venv/env
```

It creates:

```text
.venv/
├── bin/
│   └── pongo -> ../pongo/pongo.sh
├── env
└── pongo/
```

The `.venv/env` file exports:

```sh
PATH=<repo>/.venv/bin:$PATH
KONG_VERSION=3.4.2
```

Every plugin build sources this file before calling Pongo.

### 4.2 Plugin discovery

The Makefile discovers plugin directories with:

```make
PLUGIN_DIRS := $(wildcard custom-plugins/*)
```

For each directory, the package target can now handle three cases:

| Case | Input Path |
| --- | --- |
| Build from source | `custom-plugins/<folder>/*.rockspec` |
| Copy prebuilt rocks | `custom-plugins/<folder>/rocks/*.rock` or `custom-plugins/<folder>/dist/*.rock` |
| Stage native libraries | `custom-plugins/<folder>/native/**/*.so*` |

### 4.3 Packaging loop

The main packaging loop does this in simplified form:

```make
for plugin_dir in $(PLUGIN_DIRS); do \
  plugin_name=$$(basename "$$plugin_dir"); \
  if ls "$$plugin_dir"/*.rockspec >/dev/null 2>&1; then \
    (cd "$$plugin_dir" && . ../../.venv/env && pongo build --force && pongo pack); \
    mv "$$plugin_dir"/*.rock build/out/; \
  fi; \
  if ls "$$plugin_dir"/rocks/*.rock >/dev/null 2>&1; then \
    cp "$$plugin_dir"/rocks/*.rock build/out/; \
  fi; \
  if ls "$$plugin_dir"/dist/*.rock >/dev/null 2>&1; then \
    cp "$$plugin_dir"/dist/*.rock build/out/; \
  fi; \
  if [ -d "$$plugin_dir/native" ]; then \
    mkdir -p "build/out/native/$$plugin_name"; \
    cp -R "$$plugin_dir/native/." "build/out/native/$$plugin_name/"; \
  fi; \
done
```

Step by step:

1. Create `build/out`.
2. Remove old `.rock` files from `build/out`.
3. Remove old staged native files from `build/out/native`.
4. For source plugins, enter each plugin directory.
5. Source `.venv/env`.
6. Run `pongo build --force`.
7. Run `pongo pack`.
8. Move generated `.rock` files into `build/out`.
9. Copy prebuilt `.rock` files from `rocks/` or `dist/`.
10. Stage native `.so` files under `build/out/native/<plugin>/`.

Expected output:

```text
build/out/kong-plugin-request-profiler-0.1.0-1.all.rock
build/out/kong-plugin-json-field-guard-0.1.0-1.all.rock
build/out/kong-plugin-canary-header-router-0.1.0-1.all.rock
build/out/kong-plugin-saml-jwe-auth-0.1.0-1.all.rock
```

## 5. Runtime Flow: Docker Compose

The runtime command also performs packaging:

```sh
docker compose up --build
```

Compose runs one packaging job and starts three main services:

```yaml
services:
  plugin-packager:
    ...

  echo:
    ...

  keycloak:
    ...

  kong:
    ...
```

### 5.1 `echo` service

The `echo` service is a small local upstream.

Files:

```text
docker/echo-server.Dockerfile
docker/echo-server.py
```

It listens on port `8080` inside the Compose network.

Kong routes traffic to it using:

```yaml
url: http://echo:8080
```

This avoids using an external upstream like `httpbin.org`.

### 5.2 `kong` service

The Kong service builds from:

```text
docker/kong.Dockerfile
```

The image is based on:

```dockerfile
FROM kong:3.4.2
```

The Dockerfile copies in the startup installer:

```dockerfile
COPY docker/kong-install-rocks.sh /usr/local/bin/kong-install-rocks.sh
ENTRYPOINT ["/usr/local/bin/kong-install-rocks.sh"]
CMD ["kong", "docker-start"]
```

The custom entrypoint runs first. After installing plugins, it calls the official Kong Docker entrypoint.

### 5.3 `keycloak` service

The Keycloak service starts with the default local stack:

```sh
docker compose up -d keycloak
```

It uses:

```yaml
image: quay.io/keycloak/keycloak:26.4.0
command:
  - start-dev
  - --import-realm
```

The realm import file is:

```text
keycloak/realm-export.json
```

It imports:

| Item | Value |
| --- | --- |
| Realm | `kong-plugin-lab` |
| SAML client / SP entity ID | `kong-saml-auth-service` |
| Admin console | `http://localhost:18080/admin` |
| Realm metadata | `http://localhost:18080/realms/kong-plugin-lab/protocol/saml/descriptor` |

The SAML client is configured to sign both the SAML Response document and the embedded Assertion:

| Setting | Attribute | Value |
| --- | --- | --- |
| Sign SAML Response document | `saml.server.signature` | `true` |
| Sign SAML Assertion | `saml.assertion.signature` | `true` |
| Signature algorithm | `saml.signature.algorithm` | `RSA_SHA256` |
| One-time-use condition | `saml.onetimeuse.condition` | `true` |

Keycloak is intentionally decoupled from Kong plugin logic. It is only the IdP. The repo now includes a separate `saml-jwe-auth` Kong plugin that can act as the SAML SP/ACS component for local testing.

The `saml-jwe-auth` plugin does not hand-roll XML signature logic in Lua. Its Lua handler manages the browser flow, RelayState, cookies, and upstream headers; its native C bridge uses libxml2, xmlsec1, and OpenSSL for signed Response validation, signed Assertion validation, and AES-256-GCM JWE cryptography.

## 6. How Rocks Are Installed Into Kong

At runtime, Compose mounts the packaged rocks:

```yaml
volumes:
  - ./build/out:/rocks:ro
```

Inside the Kong container:

```text
/rocks/*.rock
```

The install script is:

```text
docker/kong-install-rocks.sh
```

Core logic:

```sh
for rock in "$ROCKS_DIR"/*.rock; do
  luarocks install --force "$rock"
done
```

Default environment:

```yaml
KONG_ROCKS_DIR: /rocks
KONG_REQUIRE_ROCKS: "true"
```

Behavior:

| Situation | Result |
| --- | --- |
| `/rocks` contains `.rock` files | Installs all of them |
| `/rocks` is empty and `KONG_REQUIRE_ROCKS=true` | Container exits with an error |
| `/rocks` is empty and `KONG_REQUIRE_ROCKS=false` | Container continues |

Why install at startup?

Because the `.rock` files are generated outside the runtime image by the Compose packager or `make package`, then mounted into the container. The startup script makes the runtime image generic: any `.rock` file placed in `build/out` gets installed.

For production, you may prefer to bake plugins into a custom image at build time. This repo is optimized for local development and repeatable plugin testing.

### 6.1 Native Lua FFI And C Library Support

The runtime now supports proprietary plugins that load Linux shared libraries through LuaJIT FFI or Lua C modules.

There are three supported artifact paths:

| Artifact | Put It Here | What Packaging Does |
| --- | --- | --- |
| Source plugin with a rockspec | `custom-plugins/<plugin>/*.rockspec` | Builds and packs it with LuaRocks inside the Kong `3.4.2` packager container |
| Prebuilt proprietary rock | `custom-plugins/<plugin>/rocks/*.rock` or `custom-plugins/<plugin>/dist/*.rock` | Copies it into `build/out/` |
| Native shared libraries | `custom-plugins/<plugin>/native/**/*.so*` | Stages them under `build/out/native/<plugin>/` |

If a plugin has `custom-plugins/<plugin>/native/Makefile`, the Docker Compose packager runs `make -C custom-plugins/<plugin>/native clean all` before packaging the rock. That is how `saml-jwe-auth` builds `libkong_saml_jwe_auth.so` inside the Kong 3.4.2 Linux container instead of on the host machine.

At container startup, `docker/kong-install-rocks.sh` handles native libraries before installing rocks:

```text
/rocks/native/<plugin>/*.so*
      |
      v
/usr/local/lib/kong-plugins/
```

The entrypoint then:

1. Prepends `/usr/local/lib/kong-plugins` to `LD_LIBRARY_PATH`.
2. Ensures `KONG_LUA_PACKAGE_CPATH` includes `/usr/local/lib/kong-plugins/?.so`, `/usr/local/lib/kong-plugins/lib?.so`, and the common LuaRocks C module paths under `/usr/local/lib/lua/5.1`.
3. Writes `/usr/local/lib/kong-plugins` into `/etc/ld.so.conf.d/kong-plugins-native.conf` when the image supports `ldconfig`.
4. Runs `ldconfig` when available.
5. Installs every `.rock` from `/rocks`.

Compose also preserves the native library path for Kong's Nginx worker processes:

```yaml
LD_LIBRARY_PATH: /usr/local/lib/kong-plugins
KONG_LUA_PACKAGE_CPATH: "/usr/local/lib/kong-plugins/?.so;/usr/local/lib/kong-plugins/lib?.so;/usr/local/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/?/init.so;;"
KONG_NGINX_MAIN_ENV: LD_LIBRARY_PATH
KONG_NATIVE_LIB_DIR: /usr/local/lib/kong-plugins
KONG_NATIVE_LIBS_SOURCE_DIR: /rocks/native
KONG_REQUIRE_NATIVE_LIBS: "false"
```

FFI plugins can load a library by soname when the file is named with the standard `lib<name>.so` pattern:

```lua
local ffi = require "ffi"

ffi.cdef [[
  int my_native_function(const char *input);
]]

local native = ffi.load("my_work_plugin")
```

Lua C modules can be loaded with `require` when the module filename matches the Lua module name:

```lua
local native = require "my_native_module"
```

Native compatibility requirements:

| Requirement | Why It Matters |
| --- | --- |
| Linux `.so` files only | Kong runs inside a Linux container |
| Matching CPU architecture | An `amd64` container cannot load an `arm64` `.so`, and vice versa |
| Compatible libc and linked dependencies | `ffi.load()` and Lua C `require()` ultimately use the container dynamic linker |
| No unresolved dependent libraries | If `liba.so` depends on `libb.so`, both must be staged or installed in the image |

If a proprietary rock compiles C during `docker compose build`, set:

```sh
INSTALL_NATIVE_BUILD_DEPS=true docker compose build kong
```

On PowerShell:

```powershell
$env:INSTALL_NATIVE_BUILD_DEPS = "true"
docker compose build kong
```

This enables compiler/build packages in `docker/kong.Dockerfile`. Prefer prebuilt `.rock` and `.so` artifacts when you need repeatable local runs without compiling inside the Kong image.

## 7. Installed vs Enabled vs Configured

These are three different states.

### 7.1 Installed

A plugin is installed when LuaRocks has copied its Lua files into the Kong container.

This happens here:

```sh
luarocks install --force /rocks/kong-plugin-my-plugin-0.1.0-1.all.rock
```

Installed means the Lua modules exist and can be required.

It does not mean Kong will load or run the plugin.

### 7.2 Enabled

A plugin is enabled when its name appears in `KONG_PLUGINS`.

Current Compose config:

```yaml
KONG_PLUGINS: bundled,request-profiler,json-field-guard,canary-header-router,saml-jwe-auth
```

Meaning:

| Entry | Meaning |
| --- | --- |
| `bundled` | Keep Kong's built-in plugins available |
| `request-profiler` | Load custom plugin |
| `json-field-guard` | Load custom plugin |
| `canary-header-router` | Load custom plugin |
| `saml-jwe-auth` | Load custom SAML/JWE plugin |

Enabled means Kong loads the plugin handler and schema.

It still does not mean the plugin will run on traffic.

### 7.3 Configured

A plugin is configured when there is a plugin instance in `kong/kong.yml`.

Global plugin example:

```yaml
plugins:
  - name: request-profiler
    config:
      request_header: X-Request-Id
      response_time_header: X-Kong-Elapsed
      echo_request_id: true
      log_summary: true
```

Route-level plugin example:

```yaml
routes:
  - name: guarded-json
    paths:
      - /guarded
    plugins:
      - name: json-field-guard
        config:
          required_fields:
            - customer_id
            - action
```

Configured means Kong knows where and how to execute the plugin.

Final rule:

```text
Installed + Enabled + Configured = Plugin runs on matching traffic
```

## 8. Kong DB-less Configuration

The repo runs Kong without a database:

```yaml
KONG_DATABASE: "off"
KONG_DECLARATIVE_CONFIG: /kong/declarative/kong.yml
```

The config file is mounted here:

```yaml
volumes:
  - ./kong/kong.yml:/kong/declarative/kong.yml:ro
```

So the host file:

```text
kong/kong.yml
```

becomes this container file:

```text
/kong/declarative/kong.yml
```

Kong reads it at startup.

### 8.1 Services

Current service:

```yaml
services:
  - name: local-echo
    url: http://echo:8080
```

A service represents the upstream API that Kong proxies to.

### 8.2 Routes

Current routes:

```yaml
routes:
  - name: anything
    paths:
      - /anything
    strip_path: false

  - name: guarded-json
    paths:
      - /guarded
    strip_path: true
```

Routes decide which incoming requests match a service.

For `/anything/get`:

```text
Client -> Kong /anything/get -> echo /anything/get
```

Because:

```yaml
strip_path: false
```

For `/guarded/post`:

```text
Client -> Kong /guarded/post -> echo /post
```

Because:

```yaml
strip_path: true
```

### 8.3 Global plugins

Current global plugins:

```yaml
plugins:
  - name: request-profiler
  - name: canary-header-router
```

Global plugins run on every matching proxy request unless another Kong rule limits them.

### 8.4 Route-level plugins

Current route-level plugin:

```yaml
routes:
  - name: guarded-json
    plugins:
      - name: json-field-guard
```

This means `json-field-guard` runs only for requests matching the `guarded-json` route.

## 9. Current Example Plugins

### 9.1 `request-profiler`

Files:

```text
custom-plugins/request-profiler/
├── kong-plugin-request-profiler-0.1.0-1.rockspec
└── kong/plugins/request-profiler/
    ├── handler.lua
    └── schema.lua
```

Configured globally:

```yaml
- name: request-profiler
```

Behavior:

1. During `access`, it reads or creates a request ID.
2. It sends that request ID upstream.
3. During `header_filter`, it adds elapsed time to the response.
4. During `log`, it writes a request summary to Kong logs.

Visible response headers:

```text
X-Request-Id
X-Kong-Elapsed
```

### 9.2 `json-field-guard`

Files:

```text
custom-plugins/json-field-guard/
├── kong-plugin-json-field-guard-0.1.0-1.rockspec
└── kong/plugins/json-field-guard/
    ├── handler.lua
    └── schema.lua
```

Configured on the `/guarded` route:

```yaml
- name: json-field-guard
  config:
    required_fields:
      - customer_id
      - action
    forbidden_keys:
      - password
      - ssn
      - credit_card
```

Behavior:

1. During `access`, it checks the request method.
2. It requires `Content-Type: application/json`.
3. It reads the raw body.
4. It decodes JSON.
5. It checks required fields.
6. It recursively checks forbidden keys.
7. If valid, it adds an upstream request header:

```text
X-Json-Guard: passed
```

Rejection examples:

| Problem | Status |
| --- | --- |
| Non-JSON content type | `415` |
| Invalid JSON | `400` |
| Payload too large | `413` |
| Missing required field | `422` |
| Forbidden key present | `422` |

### 9.3 `canary-header-router`

Files:

```text
custom-plugins/canary-header-router/
├── kong-plugin-canary-header-router-0.1.0-1.rockspec
└── kong/plugins/canary-header-router/
    ├── handler.lua
    └── schema.lua
```

Configured globally:

```yaml
- name: canary-header-router
  config:
    percentage: 25
```

Behavior:

1. During `access`, it checks `X-Canary-Override`.
2. If override is `canary`, it forces canary.
3. If override is `stable`, it forces stable.
4. Otherwise it calculates a deterministic bucket from a sticky value.
5. It sends the selected track upstream:

```text
X-Release-Track: stable
```

or:

```text
X-Release-Track: canary
```

Response headers:

```text
X-Release-Decision
X-Release-Reason
X-Release-Bucket
```

### 9.4 `saml-jwe-auth`

Files:

```text
custom-plugins/saml-jwe-auth/
|-- kong-plugin-saml-jwe-auth-0.1.0-1.rockspec
|-- kong/plugins/saml-jwe-auth/
|   |-- handler.lua
|   `-- schema.lua
`-- native/
    |-- Makefile
    `-- kong_saml_jwe_auth.c
```

Enabled in Compose:

```yaml
KONG_PLUGINS: bundled,request-profiler,json-field-guard,canary-header-router,saml-jwe-auth
```

Configured in the default `kong/kong.yml` only for the local SAML demo service. It protects `/saml-demo` and handles the ACS callback on `/auth`, so the existing `/anything` and `/guarded` smoke-test routes do not require browser SSO.

Behavior:

1. During `rewrite` or `access`, it handles the configured ACS path, for example `/auth`.
2. If no valid JWE is present, it creates a SAML AuthnRequest and redirects to the IdP SSO URL with the SAML HTTP-Redirect binding.
3. It encrypts RelayState as JWE so the callback can be bound to the AuthnRequest ID and original return URL.
4. On ACS POST, it validates the signed Response and signed Assertion through the native xmlsec/OpenSSL bridge.
5. It extracts the configured SAML attributes, issues an encrypted JWE session cookie, and redirects back to the original URL.
6. On later requests, it decrypts and authenticates the JWE, then sets configured upstream identity headers.

## 10. Replacing The Example Plugins

Use this exact sequence.

### Step 1: Add the plugin folder

```text
custom-plugins/my-plugin/
```

### Step 2: Add Kong plugin files

```text
custom-plugins/my-plugin/
└── kong/
    └── plugins/
        └── my-plugin/
            ├── handler.lua
            └── schema.lua
```

### Step 3: Add the rockspec

```text
custom-plugins/my-plugin/kong-plugin-my-plugin-0.1.0-1.rockspec
```

Minimum rockspec:

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

### Step 4: Add plugin name to `KONG_PLUGINS`

In `docker-compose.yml`:

```yaml
KONG_PLUGINS: bundled,my-plugin
```

For multiple plugins:

```yaml
KONG_PLUGINS: bundled,my-auth-plugin,my-transform-plugin,my-logging-plugin
```

### Step 5: Configure plugin instances in `kong/kong.yml`

Global:

```yaml
plugins:
  - name: my-plugin
    config:
      some_setting: true
```

Route-level:

```yaml
services:
  - name: local-echo
    url: http://echo:8080
    routes:
      - name: example-route
        paths:
          - /example
        plugins:
          - name: my-plugin
            config:
              some_setting: true
```

### Step 6: Package And Start

```sh
docker compose up --build
```

Compose runs the packager first and then starts Kong. To confirm the generated rock:

```sh
ls build/out
```

You should see:

```text
kong-plugin-my-plugin-0.1.0-1.all.rock
```

### Step 7: Verify install and load

Check enabled plugins:

```sh
curl http://localhost:8001/plugins/enabled
```

Check plugin schema:

```sh
curl http://localhost:8001/schemas/plugins/my-plugin
```

Check container logs:

```sh
docker compose logs kong
```

You should see lines like:

```text
installing Kong plugin rock: /rocks/kong-plugin-my-plugin-0.1.0-1.all.rock
kong-plugin-my-plugin 0.1.0-1 is now installed in /usr/local
```

### Step 8: Add smoke tests

Update:

```text
tests/postman/Kong_3_4_2_Custom_Plugins.postman_collection.json
tests/insomnia/Kong_3_4_2_Custom_Plugins.insomnia.json
tests/bash/run-curl-tests.sh
```

Add requests and assertions that prove your plugin works.

Run:

```powershell
.\tests\postman\run-collection.ps1
```

## 11. Smoke Test Automation

The runner script is:

```text
tests/postman/run-collection.ps1
```

It performs:

1. Optional packaging with `docker compose run --rm --build plugin-packager`.
2. Rock existence check in `build/out`.
3. Compose startup.
4. Kong readiness polling.
5. Newman execution.
6. JSON report export.
7. Compose shutdown.

Results file:

```text
build/postman/newman-results.json
```

Expected pass summary:

```text
Postman summary: requests=11/11, assertions=30/30, failures=0
```

Useful commands:

```powershell
.\tests\postman\run-collection.ps1
.\tests\postman\run-collection.ps1 -SkipPackage
.\tests\postman\run-collection.ps1 -KeepRunning
```

Maven also drives the Compose workflow:

```sh
mvn package
mvn verify
```

`mvn package` packages plugin rocks. `mvn verify` packages rocks, starts Kong, Keycloak, and echo, runs the Compose Newman smoke tests, runs the Keycloak SAML collection, runs the SAML browser-flow check, and stops Compose.

The script also detects busy default ports and chooses free alternatives for the run.

The Keycloak SAML runner is:

```text
tests/postman/run-keycloak-saml-collection.ps1
```

It starts the `keycloak` service if needed, waits for SAML metadata, and runs:

```text
tests/postman/Keycloak_SAML_IdP.postman_collection.json
```

Results file:

```text
build/postman/keycloak-saml-newman-results.json
```

Expected pass summary:

```text
Keycloak SAML summary: requests=11/11, assertions=26/26, failures=0
```

The SAML browser-flow check is:

```text
tests/postman/saml-browser-flow-check.js
```

Run it inside Docker Compose:

```sh
docker compose run --rm --entrypoint node newman /etc/newman/saml-browser-flow-check.js
```

The same request coverage is available without Postman:

| Format | Location | Notes |
| --- | --- | --- |
| Insomnia | `tests/insomnia/Kong_3_4_2_Custom_Plugins.insomnia.json` | Import into Insomnia and run the collection with the `Kong 3.4.2 Local` environment |
| Bash/curl | `tests/bash/run-curl-tests.sh` | Run `bash tests/bash/run-curl-tests.sh` after Kong is already running |

## 12. Verification Commands

Validate Compose syntax:

```sh
docker compose config --quiet
```

Build images:

```sh
docker compose build
```

Start services:

```sh
docker compose up --build
```

Check Kong health:

```sh
docker compose exec kong kong health
```

Check installed rocks from inside the Kong container:

```sh
docker compose exec kong luarocks list
```

Check enabled plugins:

```sh
curl http://localhost:8001/plugins/enabled
```

Check loaded config:

```sh
curl http://localhost:8001/services
curl http://localhost:8001/routes
curl http://localhost:8001/plugins
```

Run automated tests:

```sh
docker compose run --rm newman
```

Or run the curl-based checks against an already-running stack:

```sh
bash tests/bash/run-curl-tests.sh
```

## 13. Common Failure Modes

### 13.1 Rockspec filename mismatch

Symptom:

```text
Inconsistency between rockspec filename and its contents
```

Fix:

Ensure:

```lua
package = "kong-plugin-my-plugin"
version = "0.1.0-1"
```

matches:

```text
kong-plugin-my-plugin-0.1.0-1.rockspec
```

### 13.2 Plugin installed but Kong says it is not enabled

Cause:

The plugin name is missing from `KONG_PLUGINS`.

Fix:

```yaml
KONG_PLUGINS: bundled,my-plugin
```

### 13.3 Plugin enabled but Kong cannot find module

Common causes:

- `.rock` was not installed.
- Rockspec `modules` mapping is wrong.
- Folder name does not match plugin name.
- `handler.lua` or `schema.lua` was not included in the rock.

Check:

```sh
docker compose logs kong
docker compose exec kong luarocks list
```

### 13.4 Kong fails loading `kong/kong.yml`

Common causes:

- Plugin config does not match `schema.lua`.
- Plugin name in `kong.yml` does not match schema `name`.
- YAML indentation is invalid.
- A route references invalid fields.

Check config:

```sh
docker compose run --rm kong kong check /kong/declarative/kong.yml
```

### 13.5 Container exits because no rocks exist

Cause:

`KONG_REQUIRE_ROCKS=true` and `build/out` is empty.

Fix:

```sh
docker compose up --build --force-recreate
```

For debugging only, you can allow startup without rocks:

```yaml
KONG_REQUIRE_ROCKS: "false"
```

### 13.6 Host port is already allocated

For manual runs:

```powershell
$env:KONG_PROXY_PORT = "18000"
$env:KONG_ADMIN_PORT = "18001"
$env:KONG_STATUS_PORT = "18100"
docker compose up --build
```

Then use:

```text
http://localhost:18000
http://localhost:18001
http://localhost:18100/status
```

The Postman runner handles this automatically.

## 14. Development Recommendations

For custom plugins, keep the loop tight:

1. Edit `handler.lua`, `schema.lua`, or the rockspec.
2. Run `docker compose up --build --force-recreate`.
3. Watch logs:

```sh
docker compose logs -f kong
```

5. Run smoke tests:

```powershell
.\tests\postman\run-collection.ps1 -SkipPackage
```

```sh
bash tests/bash/run-curl-tests.sh
```

Use `-SkipPackage` only when you know `build/out` already contains fresh rocks.

## 15. Production Notes

This repo is a local development setup.

For production-style images, consider changing the pattern:

| Local Dev Pattern | Production-Friendly Pattern |
| --- | --- |
| Mount `build/out` into `/rocks` | Copy rocks into the image |
| Install rocks on container startup | Install rocks during Docker build |
| Run with local DB-less config | Use your platform's Kong config approach |
| Use local echo upstream | Use real upstream services |
| Use Postman smoke tests | Add CI checks and deployment validation |

The local startup installer is useful because it makes plugin iteration quick. For production, immutable images are usually easier to audit and reproduce.

## 16. Final Checklist For A New Plugin

Before calling a plugin ready, verify:

- Plugin has `handler.lua`.
- Plugin has `schema.lua`.
- Rockspec filename matches `package` and `version`.
- Rockspec `modules` paths match real files.
- `docker compose up --build` runs the packager and creates a `.rock` in `build/out`.
- Compose mounts `build/out` into `/rocks`.
- Startup logs show `luarocks install --force`.
- Plugin name appears in `KONG_PLUGINS`.
- Plugin instance appears in `kong/kong.yml`.
- Kong starts cleanly.
- Admin API shows the plugin enabled.
- Smoke tests prove the behavior.

The most important distinction is:

```text
Installed:   LuaRocks put the Lua files in the Kong container.
Enabled:     KONG_PLUGINS tells Kong to load the plugin.
Configured:  kong/kong.yml creates plugin instances.
Running:     A request matches the configured plugin scope.
```
