# 🧩 Template Usage Guide

This repo is meant to be copied, renamed, and used as a Kong plugin starter project.

The goal is simple:

```text
Add a plugin folder ➜ run docker compose up --build ➜ rocks are built ➜ Kong starts with your plugin
```

## 🚀 Default Workflow

From a fresh clone or copied repo:

```sh
docker compose up --build
```

That command now does the full local loop:

1. 📦 Runs the `plugin-packager` Compose job.
2. 🔍 Finds every plugin under `custom-plugins/`.
3. 🪨 Builds `.rock` files into `build/out/`.
4. 🧱 Starts Keycloak and the echo upstream.
5. 🦍 Starts Kong `3.4.2`.
6. ⚙️ Installs every `.rock` file into Kong.
7. 🧪 Loads plugin instances from `kong/kong.yml`.

If the stack is already running and you change plugin code, restart Kong so it installs the fresh rock:

```sh
docker compose up --build --force-recreate
```

## 🗂️ What To Copy And Edit

| File or Folder | Keep, Replace, Or Edit? | Why |
| --- | --- | --- |
| `custom-plugins/` | 🔁 Replace or add to it | Your plugin source lives here |
| `docker-compose.yml` | ✏️ Edit | Add your plugin name to `KONG_PLUGINS` |
| `kong/kong.yml` | ✏️ Edit | Add services, routes, and plugin config |
| `keycloak/realm-export.json` | ✏️ Edit if using SAML | Change realm, client ID, ACS URLs, mappers |
| `tests/postman/` | ✏️ Edit | Add smoke tests for your plugin behavior |
| `docker/` | ✅ Usually keep | Build/install machinery |
| `.env.example` | ✅ Copy to `.env` if needed | Local port/admin overrides |
| `TEST_RUNBOOK.md` | 🧪 Use as-is | Step-by-step local verification |
| `TECHNICAL_README.md` | 📚 Reference only | Deeper implementation notes |

## 🧱 Plugin Folder Shape

Create one folder per plugin:

```text
custom-plugins/my-plugin/
├── kong-plugin-my-plugin-0.1.0-1.rockspec
└── kong/
    └── plugins/
        └── my-plugin/
            ├── handler.lua
            └── schema.lua
```

The names must line up:

| Thing | Example |
| --- | --- |
| Folder | `custom-plugins/my-plugin` |
| Kong plugin name | `my-plugin` |
| Handler module | `kong.plugins.my-plugin.handler` |
| Schema module | `kong.plugins.my-plugin.schema` |
| Rockspec file | `kong-plugin-my-plugin-0.1.0-1.rockspec` |

## ⚙️ Two Places You Usually Edit

### 1. Enable The Plugin

In `docker-compose.yml`, add the plugin name to `KONG_PLUGINS`:

```yaml
KONG_PLUGINS: bundled,my-plugin
```

For several plugins:

```yaml
KONG_PLUGINS: bundled,my-auth-plugin,my-transform-plugin,my-logging-plugin
```

### 2. Configure Where It Runs

In `kong/kong.yml`, attach the plugin globally, to a service, or to a route.

Route-level example:

```yaml
services:
  - name: my-api
    url: http://echo:8080
    routes:
      - name: my-api-route
        paths:
          - /my-api
        plugins:
          - name: my-plugin
            config:
              enabled_feature: true
```

## 🪨 What Gets Built Automatically

The `plugin-packager` job handles:

- 📦 Source plugins with `*.rockspec`
- 📥 Prebuilt rocks in `custom-plugins/<plugin>/rocks/`
- 📥 Prebuilt rocks in `custom-plugins/<plugin>/dist/`
- 🧬 Native `.so` libraries under `custom-plugins/<plugin>/native/`
- 🛠️ Native builds when `custom-plugins/<plugin>/native/Makefile` exists

Generated output lands in:

```text
build/out/
```

Do not edit `build/out/` by hand. It is recreated by the build.

## 🔐 SAML Template Notes

The included SAML setup is a working local example:

| Item | Value |
| --- | --- |
| Protected route | `http://localhost:8000/saml-demo` |
| ACS callback | `http://localhost:8000/auth` |
| Keycloak admin | `http://localhost:18080/admin` |
| Admin user | `admin` / `admin` |
| Test user | `alice` / `alice-password` |

When copying this for a real SAML plugin, update:

- `keycloak/realm-export.json`
- `kong/kong.yml`
- `custom-plugins/saml-jwe-auth/`
- the Postman SAML tests

The exact working local SAML values are listed in `keycloak/README.md` under "Complete SAML Configuration Reference".

## ✅ Copy Checklist

Use this when creating a new plugin project from the template:

- 🧩 Add or replace a folder under `custom-plugins/`.
- 🪨 Make sure the rockspec filename matches `package` and `version`.
- 🧠 Make sure `handler.lua` and `schema.lua` are listed in the rockspec.
- ⚙️ Add the plugin name to `KONG_PLUGINS` in `docker-compose.yml`.
- 🛣️ Attach the plugin in `kong/kong.yml`.
- 🚀 Run `docker compose up --build`.
- 🧪 Run `docker compose run --rm newman`.
- 🧹 Do not commit secrets, customer data, `.env`, or generated `build/out/` files.
