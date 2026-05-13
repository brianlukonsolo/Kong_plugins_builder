import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class EchoHandler(BaseHTTPRequestHandler):
    server_version = "kong-plugin-echo/0.1"

    def do_GET(self):
        self._respond()

    def do_POST(self):
        self._respond()

    def do_PUT(self):
        self._respond()

    def do_PATCH(self):
        self._respond()

    def do_DELETE(self):
        self._respond()

    def log_message(self, format, *args):
        print("%s - - %s" % (self.address_string(), format % args), flush=True)

    def _respond(self):
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        raw_body = self.rfile.read(content_length).decode("utf-8") if content_length else ""

        parsed_body = None
        if raw_body:
            try:
                parsed_body = json.loads(raw_body)
            except json.JSONDecodeError:
                parsed_body = None

        response = {
            "method": self.command,
            "path": self.path,
            "headers": dict(self.headers.items()),
            "body": raw_body,
            "json": parsed_body,
        }

        encoded = json.dumps(response, sort_keys=True).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8080), EchoHandler)
    print("echo server listening on :8080", flush=True)
    server.serve_forever()
