# Insomnia Smoke Tests

Import this file into Insomnia:

```text
Kong_3_4_2_Custom_Plugins.insomnia.json
```

The export includes:

- The `Kong 3.4.2 Local` environment.
- The same 10 requests as the Postman collection.
- After-response scripts using `insomnia.test()` and `insomnia.expect()`.

Default environment values:

| Variable | Value |
| --- | --- |
| `proxy_url` | `http://localhost:8000` |
| `admin_url` | `http://localhost:8001` |
| `status_url` | `http://localhost:8100` |

If you run Kong on different host ports, update those variables in Insomnia before running the collection.
