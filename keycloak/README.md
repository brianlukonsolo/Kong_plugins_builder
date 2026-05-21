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
