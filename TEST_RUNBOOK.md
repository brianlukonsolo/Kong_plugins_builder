# 🧪 Test Runbook

Use this runbook when someone has just cloned or copied the repo and wants to prove the template works end to end.

## ✅ Prerequisites

You need:

- Docker Desktop running
- Docker Compose available as `docker compose`
- Ports free unless overridden in `.env`:
  - `8000` Kong proxy
  - `8001` Kong Admin API
  - `8100` Kong status API
  - `18080` Keycloak

Optional local overrides:

```sh
cp .env.example .env
```

## 1. 🧹 Start From A Clean Stack

```sh
docker compose down --remove-orphans
```

Expected result:

```text
Containers are stopped and removed.
```

## 2. 🚀 Build And Start Everything

```sh
docker compose up -d --build --wait --wait-timeout 240
```

This single command:

1. 📦 Builds plugin rocks with `plugin-packager`.
2. 🪨 Writes rocks into `build/out/`.
3. 🔐 Starts Keycloak.
4. 🧪 Starts the echo upstream.
5. 🦍 Starts Kong.
6. ⚙️ Installs the generated rocks into Kong.

Expected result:

```text
plugin-packager exited with code 0
kong is healthy
keycloak is healthy
```

## 3. 🔎 Check Containers

```sh
docker compose ps -a
```

Expected services:

| Service | Expected Status |
| --- | --- |
| `plugin-packager` | `Exited (0)` |
| `echo` | running |
| `keycloak` | healthy |
| `kong` | healthy |

## 4. 🦍 Check Kong In The Browser

Open:

```text
http://localhost:8100/status
```

Expected result:

```text
Kong status JSON is returned.
```

Open:

```text
http://localhost:8001/
```

Expected result:

```text
Kong Admin API JSON is returned and version is 3.4.2.
```

## 5. 🔐 Check Keycloak In The Browser

Open:

```text
http://localhost:18080/admin
```

Log in with:

```text
username: admin
password: admin
```

Then select:

```text
Realm: kong-plugin-lab
Client: kong-saml-auth-service
```

Check the SAML metadata:

```text
http://localhost:18080/realms/kong-plugin-lab/protocol/saml/descriptor
```

Expected result:

```text
XML metadata is returned and contains a signing certificate.
```

The full table of working SAML values is in `keycloak/README.md` under "Complete SAML Configuration Reference".

## 6. 🧪 Run The Main Smoke Tests

```sh
docker compose run --rm newman
```

Expected summary:

```text
requests: 11 executed, 0 failed
assertions: 30 executed, 0 failed
```

This checks:

- Kong status API
- Kong Admin API
- Kong version
- custom plugins are enabled
- request profiler behavior
- canary routing behavior
- JSON guard pass/fail behavior
- SAML protected route starts login

## 7. 🔐 Run Keycloak SAML Tests

```sh
docker compose run --rm --no-deps newman run /etc/newman/Keycloak_SAML_IdP.postman_collection.json -e /etc/newman/keycloak.postman_environment.json --env-var keycloak_url=http://keycloak:8080 --env-var admin_username=admin --env-var admin_password=admin
```

Expected summary:

```text
requests: 11 executed, 0 failed
assertions: 26 executed, 0 failed
```

This checks:

- SAML metadata
- SSO/SLO endpoints
- malformed SAML rejection paths
- signed Response setting
- signed Assertion setting
- SAML client config
- SAML user and mappers

## 8. 🧭 Test The SAML Browser Flow

Automated check:

```sh
docker compose run --rm --entrypoint node newman /etc/newman/saml-browser-flow-check.js
```

Expected result:

```text
large_acs_form_body=400
start_login=302
keycloak_login_page=200
keycloak_saml_response_form=200
kong_acs=302
final_saml_demo=200
authenticated_user=alice
authenticated_email=alice@example.test
```

Manual browser check:

1. Open `http://localhost:8000/saml-demo`.
2. Kong redirects to Keycloak.
3. Log in with `alice` / `alice-password`.
4. Keycloak posts the signed `SAMLResponse` to `http://localhost:8000/auth`.
5. Kong validates the response and sets the `kong_saml_session` JWE cookie.
6. Browser redirects back to `/saml-demo`.
7. The final echo JSON should include:

```text
X-Authenticated-User: alice
X-Authenticated-Email: alice@example.test
```

Inspect the SAML response debug logs:

```powershell
docker compose logs -f kong | Select-String "saml-jwe-auth debug"
```

The local `kong/kong.yml` demo config currently has `debug_enabled`, `debug_log_saml_response`, and `debug_log_max_bytes` turned on for this SAML route. The log shows the received `SAMLResponse` POST value, decoded SAML XML, validation result, subject, and mapped attributes.

For the full copyable base64 value, use the capture file written to `build/saml-debug`:

```powershell
$latest = Get-ChildItem .\build\saml-debug\*_saml-response.b64 | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content -Raw $latest.FullName
```

The matching decoded XML file uses the same prefix and ends with `_saml-response.xml`.

Turn `debug_log_saml_response` and `debug_capture_dir` off after troubleshooting if you do not want signed SAML XML and user attributes in logs or local capture files.

## 9. 🧩 Test A New Plugin

After adding a new plugin under `custom-plugins/`:

1. Add the plugin name to `KONG_PLUGINS` in `docker-compose.yml`.
2. Add the plugin config to `kong/kong.yml`.
3. Restart with fresh rocks:

```sh
docker compose up -d --build --force-recreate --wait --wait-timeout 240
```

4. Check enabled plugins:

```sh
curl http://localhost:8001/plugins/enabled
```

5. Run the smoke tests:

```sh
docker compose run --rm newman
```

## 10. 📋 Useful URLs

| Purpose | URL |
| --- | --- |
| Kong proxy | `http://localhost:8000` |
| Kong Admin API | `http://localhost:8001` |
| Kong status API | `http://localhost:8100/status` |
| Keycloak admin | `http://localhost:18080/admin` |
| Keycloak SAML metadata | `http://localhost:18080/realms/kong-plugin-lab/protocol/saml/descriptor` |
| SAML protected route | `http://localhost:8000/saml-demo` |
| SAML ACS callback | `http://localhost:8000/auth` |

## 11. 🧯 Troubleshooting

If Kong says no rocks were found:

```sh
docker compose up -d --build --force-recreate --wait --wait-timeout 240
```

If Keycloak config looks stale:

```sh
docker compose rm -sf keycloak
docker compose up -d --build --wait --wait-timeout 240
```

If ports are busy, copy `.env.example` to `.env` and change the port values.

If you want logs:

```sh
docker compose logs -f kong
docker compose logs -f keycloak
```

## 12. 🧹 Stop Everything

```sh
docker compose down
```

For a full clean stop:

```sh
docker compose down --remove-orphans
```
