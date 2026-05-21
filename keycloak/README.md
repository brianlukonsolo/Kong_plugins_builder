# Keycloak Local IdP

This folder contains a local Keycloak realm export for SAML development.

It is intentionally decoupled from the Kong plugins. Keycloak is only the IdP. A separate SAML service provider/auth service should validate SAML responses and then issue a short-lived internal token or session for Kong to enforce.

## Start Keycloak

```sh
docker compose --profile idp up -d keycloak
```

Plain `docker compose up --build` does not start Keycloak because this service is behind the optional `idp` profile.

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
KEYCLOAK_ADMIN=my-admin KEYCLOAK_ADMIN_PASSWORD=my-password docker compose --profile idp up -d keycloak
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
http://localhost:8000/saml/acs
http://localhost:8082/saml/acs
```

There is no SAML auth service in this repo yet. Those ACS URLs are placeholders for the decoupled service provider component that should validate SAML and issue an internal session/JWT for Kong.

## Verify Import

```sh
docker compose --profile idp up -d keycloak
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
docker compose --profile idp rm -sf keycloak
docker compose --profile idp up -d keycloak
```
