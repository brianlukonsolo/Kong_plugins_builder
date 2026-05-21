# Keycloak Local IdP

This folder contains a local Keycloak realm export for SAML development.

It is intentionally decoupled from the Kong plugin implementation. Keycloak is only the IdP. The `saml-jwe-auth` Kong plugin is the local SAML service provider / ACS component that validates SAML responses and then issues an encrypted JWE session for Kong to enforce.

## Start Keycloak

```sh
docker compose up -d keycloak
```

Plain `docker compose up --build` starts Keycloak with Kong and the echo upstream.

Admin console:

```text
http://localhost:18080/admin
```

Default local credentials:

```text
username: admin
password: admin
```

Override them without editing the repo:

```sh
KEYCLOAK_ADMIN=my-admin KEYCLOAK_ADMIN_PASSWORD=my-password docker compose up -d keycloak
```

## Imported Realm

Realm:

```text
kong-plugin-lab
```

SAML client / SP entity ID:

```text
kong-saml-auth-service
```

Local test user:

```text
username: alice
password: alice-password
```

The local password is for development only. Do not use this realm export as a production realm.

## SAML Signing Settings

The SAML client is configured to require the IdP to sign both levels of the SAML response:

| Setting | Realm Export Attribute | Value |
| --- | --- | --- |
| Sign SAML Response document | `saml.server.signature` | `true` |
| Sign SAML Assertion | `saml.assertion.signature` | `true` |
| Signature algorithm | `saml.signature.algorithm` | `RSA_SHA256` |
| Canonicalization | `saml_signature_canonicalization_method` | Exclusive XML canonicalization |
| One-time-use condition | `saml.onetimeuse.condition` | `true` |
| Require signed SP AuthnRequests | `saml.client.signature` | `false` |

`saml.client.signature=false` means Keycloak does not require the future SP/auth service to sign login requests. That keeps local setup simple. In a stricter deployment, enable signed AuthnRequests after the auth service has its own SP signing key.

## Complete SAML Configuration Reference

These are the exact values currently used by the working local SAML flow.

### 🧱 Docker / Keycloak Service Values

| Name | Value | Comment |
| --- | --- | --- |
| `KEYCLOAK_PORT` | `18080` | Host port for Keycloak. Browser URL is `http://localhost:18080`. |
| `KEYCLOAK_ADMIN` | `admin` | Local admin username used by Docker Compose unless overridden. |
| `KEYCLOAK_ADMIN_PASSWORD` | `admin` | Local admin password used by Docker Compose unless overridden. |
| `KC_BOOTSTRAP_ADMIN_USERNAME` | `${KEYCLOAK_ADMIN:-admin}` | Creates the local Keycloak admin user on first startup. |
| `KC_BOOTSTRAP_ADMIN_PASSWORD` | `${KEYCLOAK_ADMIN_PASSWORD:-admin}` | Creates the local Keycloak admin password on first startup. |
| `KC_HEALTH_ENABLED` | `true` | Enables the health endpoint used by Compose readiness checks. |
| `KC_HTTP_ENABLED` | `true` | Enables HTTP for local development. |
| `KC_HTTP_PORT` | `8080` | Keycloak listens on port `8080` inside the Compose network. |
| `KC_HOSTNAME_STRICT` | `false` | Allows local `localhost` and Compose-network access. |
| Keycloak image | `quay.io/keycloak/keycloak:26.4.0` | Runtime image used by the local IdP. |
| Keycloak command | `start-dev --import-realm --hostname-strict=false --http-enabled=true` | Starts Keycloak in local dev mode and imports `realm-export.json`. |
| Realm import path | `/opt/keycloak/data/import/kong-plugin-lab-realm.json` | Container path where Compose mounts `keycloak/realm-export.json`. |

### 🔐 Realm Values

| Name | Value | Comment |
| --- | --- | --- |
| `realm` | `kong-plugin-lab` | Local Keycloak realm used by the SAML tests. |
| `displayName` | `Kong Plugin Lab` | Display name shown in the Keycloak admin UI. |
| `enabled` | `true` | Realm is active. |
| `sslRequired` | `none` | Allows HTTP localhost SAML testing. Do not use this setting for production. |
| `registrationAllowed` | `false` | Self-registration is disabled. |
| `loginWithEmailAllowed` | `true` | Users can log in with email as well as username. |
| `bruteForceProtected` | `true` | Local realm has brute-force protection enabled. |

### 🪪 SAML Client / SP Values

| Name | Value | Comment |
| --- | --- | --- |
| `clientId` | `kong-saml-auth-service` | SAML SP entity ID expected by the Kong plugin as `sp_entity_id`. |
| `name` | `Kong SAML Auth Service` | Display name in Keycloak. |
| `description` | `Local SAML SP configuration for the Kong saml-jwe-auth plugin.` | Notes what the client is for. |
| `enabled` | `true` | SAML client is active. |
| `protocol` | `saml` | Makes this a SAML client, not OIDC. |
| `publicClient` | `true` | No client secret is used for this local SAML client. |
| `frontchannelLogout` | `true` | Enables browser/front-channel logout support. |
| `redirectUris[0]` | `http://localhost:8000/auth` | Main ACS callback used by the Kong plugin. |
| `redirectUris[1]` | `http://localhost:8000/saml/acs` | Local development alternative ACS URL. |
| `redirectUris[2]` | `http://localhost:8082/saml/acs` | Local development alternative ACS URL. |
| `defaultClientScopes` | `[]` | No default scopes are attached. |
| `optionalClientScopes` | `[]` | No optional scopes are attached. |

### ✍️ SAML Client Attributes

| Name | Value | Comment |
| --- | --- | --- |
| `saml.assertion.signature` | `true` | Keycloak signs the embedded SAML Assertion. |
| `saml.authnstatement` | `true` | Includes an AuthnStatement in the Assertion. |
| `saml.client.signature` | `false` | Keycloak does not require signed SP AuthnRequests in local dev. |
| `saml.encrypt` | `false` | Assertions are signed but not encrypted. |
| `saml.force.post.binding` | `true` | Keycloak sends the SAML response to ACS using HTTP POST binding. |
| `saml_force_name_id_format` | `true` | Forces the configured NameID format. |
| `saml_name_id_format` | `username` | NameID value is the Keycloak username, so Alice becomes `alice`. |
| `saml.onetimeuse.condition` | `true` | Adds a OneTimeUse condition to assertions. |
| `saml.server.signature` | `true` | Keycloak signs the outer SAML Response document. |
| `saml.server.signature.keyinfo.ext` | `false` | Does not include extended KeyInfo. |
| `saml.signature.algorithm` | `RSA_SHA256` | Signature algorithm required by the local validation flow. |
| `saml_signature_canonicalization_method` | `http://www.w3.org/2001/10/xml-exc-c14n#` | Exclusive XML canonicalization. |
| `saml_single_logout_service_url_post` | `http://localhost:8000/saml/sls` | Local SLO POST URL placeholder. |
| `saml_single_logout_service_url_redirect` | `http://localhost:8000/saml/sls` | Local SLO Redirect URL placeholder. |
| `saml_assertion_consumer_url_post` | `http://localhost:8000/auth` | ACS URL for SAML HTTP POST responses. |
| `saml_assertion_consumer_url_redirect` | `http://localhost:8000/auth` | ACS URL also listed for Redirect binding compatibility. |
| `saml_idp_initiated_sso_url_name` | `kong-saml-auth-service` | IdP-initiated SSO client URL suffix. |
| `saml_idp_initiated_sso_relay_state` | empty string | No fixed RelayState for IdP-initiated SSO. |

### 🧾 SAML Attribute Mappers

| Name | Value | Comment |
| --- | --- | --- |
| `email.protocolMapper` | `saml-user-property-mapper` | Maps a Keycloak user property into a SAML attribute. |
| `email.attribute.name` | `email` | SAML attribute name read by the Kong plugin. |
| `email.attribute.nameformat` | `Basic` | Uses the basic SAML attribute name format. |
| `email.friendly.name` | `email` | Friendly display name in metadata/assertions. |
| `email.user.attribute` | `email` | Source user property. |
| `given_name.protocolMapper` | `saml-user-property-mapper` | Maps first name into SAML. |
| `given_name.attribute.name` | `given_name` | SAML attribute name read by the Kong plugin. |
| `given_name.attribute.nameformat` | `Basic` | Uses the basic SAML attribute name format. |
| `given_name.friendly.name` | `given_name` | Friendly display name in metadata/assertions. |
| `given_name.user.attribute` | `firstName` | Source user property. |
| `family_name.protocolMapper` | `saml-user-property-mapper` | Maps last name into SAML. |
| `family_name.attribute.name` | `family_name` | SAML attribute name read by the Kong plugin. |
| `family_name.attribute.nameformat` | `Basic` | Uses the basic SAML attribute name format. |
| `family_name.friendly.name` | `family_name` | Friendly display name in metadata/assertions. |
| `family_name.user.attribute` | `lastName` | Source user property. |
| `groups.protocolMapper` | `saml-group-membership-mapper` | Maps Keycloak group membership into SAML. |
| `groups.attribute.name` | `groups` | SAML attribute name read by the Kong plugin. |
| `groups.attribute.nameformat` | `Basic` | Uses the basic SAML attribute name format. |
| `groups.full.path` | `false` | Emits group names like `api-admins`, not `/api-admins`. |
| `groups.single` | `false` | Allows multiple group values. |

### 👤 Local Test User Values

| Name | Value | Comment |
| --- | --- | --- |
| `users[0].username` | `alice` | Test user used for the browser journey. |
| `users[0].enabled` | `true` | User is active. |
| `users[0].emailVerified` | `true` | Email is treated as verified. |
| `users[0].firstName` | `Alice` | Emitted as SAML `given_name`. |
| `users[0].lastName` | `Example` | Emitted as SAML `family_name`. |
| `users[0].email` | `alice@example.test` | Emitted as SAML `email`. |
| `users[0].groups[0]` | `/engineering` | Alice belongs to this local group. |
| `users[0].groups[1]` | `/api-admins` | Alice belongs to this local group and it appears upstream as `api-admins`. |
| `users[0].credentials[0].type` | `password` | Local test credential type. |
| `users[0].credentials[0].value` | `alice-password` | Local test password. |
| `users[0].credentials[0].temporary` | `false` | Password does not need to be reset on login. |

### 🦍 Kong Plugin SAML Values

These values live in `kong/kong.yml` under the `saml-jwe-auth` plugin config.

| Name | Value | Comment |
| --- | --- | --- |
| `route` | `/saml-demo` | Browser-protected demo route. |
| `acs_path` | `/auth` | Kong path where Keycloak posts `SAMLResponse` and `RelayState`. |
| `idp_sso_url` | `http://localhost:18080/realms/kong-plugin-lab/protocol/saml` | Browser-facing Keycloak SAML endpoint used for AuthnRequest redirects. |
| `idp_metadata_url` | `http://keycloak:8080/realms/kong-plugin-lab/protocol/saml/descriptor` | Internal Compose URL used by Kong to fetch the IdP signing certificate. |
| `idp_entity_id` | `http://localhost:18080/realms/kong-plugin-lab` | Issuer expected in Keycloak SAML responses. |
| `sp_entity_id` | `kong-saml-auth-service` | Must match the Keycloak SAML client `clientId`. |
| `assertion_consumer_service_url` | `http://localhost:8000/auth` | ACS URL embedded in AuthnRequests and checked during response validation. |
| `jwe_key` | `local-dev-saml-jwe-key-change-me-32-bytes` | Local development key for encrypted RelayState and session JWE. Replace outside local dev. |
| `session_cookie_name` | `kong_saml_session` | Cookie set after successful SAML validation. |
| `session_cookie_secure` | `false` | Allows HTTP localhost cookie testing. Use `true` behind HTTPS. |
| `session_cookie_same_site` | `Lax` | Cookie SameSite mode for the local browser flow. |
| `session_ttl_seconds` | `3600` | JWE session lifetime. |
| `relay_state_ttl_seconds` | `300` | Encrypted RelayState lifetime while the user is at the IdP. |
| `clock_skew_seconds` | `120` | Allowed SAML assertion clock skew. |
| `require_replay_protection` | `true` | Stores assertion IDs in Kong shared memory to block replay. |
| `attribute_mappings[0].claim` | `email` | JWE claim name for email. |
| `attribute_mappings[0].saml_attribute` | `email` | SAML attribute read from the Assertion. |
| `attribute_mappings[0].upstream_header` | `X-Authenticated-Email` | Header sent to the upstream. |
| `attribute_mappings[1].claim` | `given_name` | JWE claim name for first name. |
| `attribute_mappings[1].saml_attribute` | `given_name` | SAML attribute read from the Assertion. |
| `attribute_mappings[1].upstream_header` | `X-Authenticated-Given-Name` | Header sent to the upstream. |
| `attribute_mappings[2].claim` | `family_name` | JWE claim name for last name. |
| `attribute_mappings[2].saml_attribute` | `family_name` | SAML attribute read from the Assertion. |
| `attribute_mappings[2].upstream_header` | `X-Authenticated-Family-Name` | Header sent to the upstream. |
| `attribute_mappings[3].claim` | `groups` | JWE claim name for group membership. |
| `attribute_mappings[3].saml_attribute` | `groups` | SAML attribute read from the Assertion. |
| `attribute_mappings[3].upstream_header` | `X-Authenticated-Groups` | Header sent to the upstream. |

### 🌐 Working Local URLs

| Name | Value | Comment |
| --- | --- | --- |
| Keycloak admin | `http://localhost:18080/admin` | Admin UI for checking realm/client settings. |
| Keycloak metadata | `http://localhost:18080/realms/kong-plugin-lab/protocol/saml/descriptor` | Browser-facing IdP metadata URL. |
| Keycloak SAML endpoint | `http://localhost:18080/realms/kong-plugin-lab/protocol/saml` | SSO endpoint used by the plugin. |
| IdP-initiated SSO URL | `http://localhost:18080/realms/kong-plugin-lab/protocol/saml/clients/kong-saml-auth-service` | Useful for checking the client login page. |
| Kong protected route | `http://localhost:8000/saml-demo` | Start the browser login journey here. |
| Kong ACS callback | `http://localhost:8000/auth` | Keycloak posts `SAMLResponse` here. |

## URLs

Realm metadata:

```text
http://localhost:18080/realms/kong-plugin-lab/protocol/saml/descriptor
```

IdP-initiated SSO URL:

```text
http://localhost:18080/realms/kong-plugin-lab/protocol/saml/clients/kong-saml-auth-service
```

Configured ACS URLs:

```text
http://localhost:8000/auth
http://localhost:8000/saml/acs
http://localhost:8082/saml/acs
```

`http://localhost:8000/auth` matches the default `acs_path` used by the `saml-jwe-auth` plugin. The other ACS URLs are retained as local development alternatives.

## Browser Check

Start the stack:

```sh
docker compose up -d --build --wait --wait-timeout 240
```

Then open:

```text
http://localhost:8000/saml-demo
```

Log in with:

```text
username: alice
password: alice-password
```

Keycloak posts the signed SAML response to `http://localhost:8000/auth`. Kong validates it, sets the `kong_saml_session` JWE cookie, and redirects back to `/saml-demo`.

If Keycloak was already running before this file changed, recreate the container to re-import the realm:

```sh
docker compose rm -sf keycloak
docker compose up -d keycloak
```

## Verify Import

```sh
docker compose up -d keycloak
curl http://localhost:18080/realms/kong-plugin-lab/protocol/saml/descriptor
```

You should receive XML metadata containing the `kong-plugin-lab` realm descriptor.

## Run The Postman SAML Tests

From the repo root:

```powershell
.\tests\postman\run-keycloak-saml-collection.ps1
```

This runs `tests/postman/Keycloak_SAML_IdP.postman_collection.json` through Dockerized Newman. It checks SAML metadata, SSO/SLO/artifact metadata, malformed SAML rejection paths, signed Response config, signed Assertion config, signature algorithm, ACS/logout URLs, SAML mappers, and the local test user.

## Reset Local Keycloak State

The Keycloak container uses container-local dev storage. To force a fresh import:

```sh
docker compose rm -sf keycloak
docker compose up -d keycloak
```
