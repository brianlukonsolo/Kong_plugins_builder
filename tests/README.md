# Test Assets

This folder keeps the same Kong smoke-test coverage in three formats:

- `postman/` - Postman collection, environment, and Newman runner.
- `insomnia/` - Insomnia v4 export with after-response assertions.
- `bash/` - Bash runner that executes the same requests with `curl`.

Start Kong before using the Insomnia or Bash tests:

```sh
make package
docker compose up --build
```

The Postman runner still manages packaging, Docker Compose startup, port selection, and shutdown for you:

```powershell
.\tests\postman\run-collection.ps1
```
