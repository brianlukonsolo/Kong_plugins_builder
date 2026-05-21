# Test Assets

This folder keeps the same Kong smoke-test coverage in three formats:

- `postman/` - Postman collection, environment, and Newman runner.
- `insomnia/` - Insomnia v4 export with after-response assertions.
- `bash/` - Bash runner that executes the same requests with `curl`.

Start Kong before using the Insomnia or Bash tests:

```sh
docker compose up --build
```

That packages plugins, starts Kong, starts the echo upstream, and starts Keycloak. The protected SAML demo is available at `http://localhost:8000/saml-demo`, with ACS callback at `http://localhost:8000/auth`.

The Postman runner still manages packaging, Docker Compose startup, port selection, and shutdown for you:

```powershell
.\tests\postman\run-collection.ps1
```

The full SAML browser-flow check runs inside Docker Compose:

```powershell
docker compose run --rm --entrypoint node newman /etc/newman/saml-browser-flow-check.js
```
