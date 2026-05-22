# saml-jwe-auth

`saml-jwe-auth` is a Kong plugin that performs browser SAML SSO at the gateway and then issues an encrypted JWE session for later requests.

The plugin is decoupled from Keycloak. Keycloak is only the IdP. The plugin accepts standard SAML HTTP-POST responses from any IdP that can sign both the SAML `Response` and the embedded `Assertion`.

## Flow

```text
Browser requests protected API through Kong
      |
      | no valid JWE session
      v
Kong plugin redirects to the IdP with a SAML AuthnRequest
      |
      v
IdP login page
      |
      | POST SAMLResponse + RelayState to ACS
      v
Kong plugin ACS path, for example /auth
      |
      | validates signed Response, signed Assertion, issuer, audience,
      | destination, recipient, timestamps, InResponseTo, and replay
      v
Kong plugin sets encrypted JWE session cookie
      |
      v
Browser is redirected to original API URL
      |
      | valid JWE session
      v
Kong forwards request upstream with configured identity headers
```

## Files

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

The Lua handler owns Kong phases, redirects, RelayState, cookies, and JWE compact serialization. The native C library owns cryptographic operations through libxml2, xmlsec1, and OpenSSL.

## What The Native Library Validates

The C bridge requires:

- The document root is a SAML 2.0 `Response`.
- The `Response` has a direct XML signature.
- The embedded `Assertion` has a direct XML signature.
- Both signatures validate against the configured IdP certificate.
- Signature `Reference URI` values match the signed `Response` and `Assertion` IDs.
- `Response Destination` matches the configured ACS URL.
- `Response Issuer` matches the configured IdP entity ID.
- `StatusCode` is SAML success.
- `Conditions` contain the configured SP entity ID as an audience.
- `NotBefore` and `NotOnOrAfter` are valid with configurable clock skew.
- `SubjectConfirmationData Recipient` matches the configured ACS URL.

The Lua handler also checks `InResponseTo` against encrypted RelayState and records assertion IDs in an OpenResty shared dictionary for replay protection.

## JWE Session

The plugin issues compact JWE using:

```text
alg=dir
enc=A256GCM
```

The configured `jwe_key` must be at least 32 characters. A 32-byte value is used directly; longer values are SHA-256 hashed to a 32-byte AES key.

The JWE payload contains:

```json
{
  "typ": "saml-session",
  "iss": "saml-jwe-auth",
  "sub": "NameID from assertion",
  "attrs": {
    "configured_claim": "configured SAML attribute value"
  },
  "iat": 1710000000,
  "exp": 1710003600
}
```

The same JWE format is also used for RelayState so the plugin can bind the IdP callback to the original AuthnRequest ID and return URL.

## Example Kong Config

This repo enables the plugin in `KONG_PLUGINS` and attaches it to the local SAML demo service. The protected demo route is `/saml-demo`; the ACS callback route is `/auth`. The normal `/anything` and `/guarded` smoke-test routes are separate and do not require SAML login.

Example global DB-less config:

```yaml
plugins:
  - name: saml-jwe-auth
    config:
      acs_path: /auth
      idp_sso_url: http://localhost:18080/realms/kong-plugin-lab/protocol/saml
      idp_metadata_url: http://keycloak:8080/realms/kong-plugin-lab/protocol/saml/descriptor
      idp_entity_id: http://localhost:18080/realms/kong-plugin-lab
      sp_entity_id: kong-saml-auth-service
      assertion_consumer_service_url: http://localhost:8000/auth
      jwe_key: change-this-local-dev-key-32-bytes
      session_cookie_name: kong_saml_session
      session_cookie_secure: false
      session_cookie_same_site: Lax
      debug_enabled: false
      debug_log_saml_response: false
      debug_log_max_bytes: 4096
      debug_capture_dir: ""
      attribute_mappings:
        - claim: email
          saml_attribute: email
          upstream_header: X-Authenticated-Email
```

With global placement, the plugin can answer `/auth` in the `rewrite` phase before Kong routing completes. For route-level placement, the ACS path must also match a Kong route where the plugin runs.

## Keycloak Settings

For the included local Keycloak realm:

| Setting | Value |
| --- | --- |
| Realm | `kong-plugin-lab` |
| SAML client / SP entity ID | `kong-saml-auth-service` |
| ACS URL for this plugin | `http://localhost:8000/auth` |
| IdP SSO URL | `http://localhost:18080/realms/kong-plugin-lab/protocol/saml` |
| Response signature | enabled |
| Assertion signature | enabled |
| Signature algorithm | `RSA_SHA256` |

The plugin can fetch the IdP signing certificate from metadata:

```text
http://localhost:18080/realms/kong-plugin-lab/protocol/saml/descriptor
```

For local Compose, `kong/kong.yml` uses the internal metadata URL `http://keycloak:8080/realms/kong-plugin-lab/protocol/saml/descriptor`. You can also configure `idp_certificate_pem` directly if you want certificate pinning without metadata fetches.

The complete working Keycloak/Kong SAML value table is in `keycloak/README.md` under "Complete SAML Configuration Reference".

## Debug SAML Responses

The plugin has an explicit local debug mode for inspecting the ACS callback. The checked-in demo config in `kong/kong.yml` enables it so you can see what Keycloak posts back to Kong.

| Config | Local value | What it does |
| --- | --- | --- |
| `debug_enabled` | `true` | Writes SAML flow debug lines to the Kong container log. |
| `debug_log_saml_response` | `true` | Logs the raw `SAMLResponse` POST value and the decoded XML. |
| `debug_log_max_bytes` | `20000` | Truncates large logged SAML values after this many bytes. |
| `debug_capture_dir` | `/kong-saml-debug` | Writes full, copyable debug files into the mounted `saml-plugin-outputs` folder. |

Watch the plugin logs while you run the browser flow:

```powershell
docker compose logs -f kong | Select-String "saml-jwe-auth debug"
```

On a shell with `grep`:

```sh
docker compose logs -f kong | grep "saml-jwe-auth debug"
```

The interesting lines are:

```text
[saml-jwe-auth debug] received ACS POST saml_response_b64_bytes=...
[saml-jwe-auth debug] SAMLResponse POST value bytes=...
[saml-jwe-auth debug] decoded SAMLResponse XML bytes=...
[saml-jwe-auth debug] wrote debug capture file=/kong-saml-debug/...
[saml-jwe-auth debug] SAML response signature and conditions validated
[saml-jwe-auth debug] SAML attributes=...
```

For full copy/paste values, use the files written under `saml-plugin-outputs` on the host:

```powershell
$latest = Get-ChildItem .\saml-plugin-outputs\*_saml-response.b64 | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content -Raw $latest.FullName
```

Each successful ACS POST writes matching files:

```text
<timestamp>_<request-id>_saml-response.b64
<timestamp>_<request-id>_saml-response.xml
<timestamp>_<request-id>_relay-state.txt
<timestamp>_<request-id>_manifest.json
```

The decoded XML and capture files contain user identity data and signed assertion material. Keep `debug_log_saml_response` and `debug_capture_dir` off anywhere outside local troubleshooting.

## Build And Verify

Package with Docker Compose:

```sh
docker compose run --rm --build plugin-packager
```

Start the full local stack:

```sh
docker compose up -d --build --wait --wait-timeout 240
```

Run the existing smoke tests:

```sh
docker compose run --rm newman
```

Run the full SAML browser-flow check:

```sh
docker compose run --rm --entrypoint node newman /etc/newman/saml-browser-flow-check.js
```

Or run the full Maven-driven flow:

```sh
mvn verify
```

## Implementation Limits

This is a real gateway plugin implementation, but before using it for production traffic you should add more negative security fixtures for XML signature wrapping, expired assertions, bad audiences, bad recipients, replayed assertions, and IdP certificate rotation. The current implementation sends AuthnRequests with the SAML HTTP-Redirect binding and accepts SAML HTTP-POST responses at the ACS. It does not yet sign SP AuthnRequests or handle encrypted assertions.
