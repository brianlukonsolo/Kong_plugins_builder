# Bash Curl Smoke Tests

Run this from the repo root after Kong is running:

```sh
bash tests/bash/run-curl-tests.sh
```

The script uses only Bash and `curl`. It calls the same 10 endpoints as the Postman collection and fails with a non-zero exit code if any assertion fails.

Override URLs when Kong is running on non-default ports:

```sh
PROXY_URL=http://localhost:18000 \
ADMIN_URL=http://localhost:18001 \
STATUS_URL=http://localhost:18100 \
bash tests/bash/run-curl-tests.sh
```
