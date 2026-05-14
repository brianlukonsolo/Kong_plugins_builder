#!/usr/bin/env bash
set -uo pipefail

PROXY_URL="${PROXY_URL:-http://localhost:${KONG_PROXY_PORT:-8000}}"
ADMIN_URL="${ADMIN_URL:-http://localhost:${KONG_ADMIN_PORT:-8001}}"
STATUS_URL="${STATUS_URL:-http://localhost:${KONG_STATUS_PORT:-8100}}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

requests=0
assertions=0
failures=0
body_file=""
headers_file=""
status_code=""

pass() {
  assertions=$((assertions + 1))
  printf '  ok - %s\n' "$1"
}

fail() {
  assertions=$((assertions + 1))
  failures=$((failures + 1))
  printf '  not ok - %s\n' "$1" >&2
}

run_curl() {
  local name="$1"
  shift

  requests=$((requests + 1))
  body_file="$tmp_dir/$requests.body"
  headers_file="$tmp_dir/$requests.headers"
  : > "$body_file"
  : > "$headers_file"

  printf '\n--> %s\n' "$name"
  if ! status_code="$(curl -sS -D "$headers_file" -o "$body_file" -w '%{http_code}' "$@")"; then
    failures=$((failures + 1))
    printf '  curl failed for %s\n' "$name" >&2
    status_code="000"
  fi
}

header_value() {
  local wanted="$1"
  awk -v wanted="$wanted" '
    BEGIN { wanted = tolower(wanted) }
    {
      key = $0
      sub(/:.*/, "", key)
      if (tolower(key) == wanted) {
        sub(/^[^:]*:[[:space:]]*/, "")
        sub(/\r$/, "")
        print
        exit
      }
    }
  ' "$headers_file"
}

assert_status() {
  local expected="$1"
  local label="$2"

  if [[ "$status_code" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (expected $expected, got $status_code)"
    sed 's/^/    body: /' "$body_file" >&2
  fi
}

assert_body_contains() {
  local expected="$1"
  local label="$2"

  if grep -Fq "$expected" "$body_file"; then
    pass "$label"
  else
    fail "$label"
    printf '    missing body text: %s\n' "$expected" >&2
    sed 's/^/    body: /' "$body_file" >&2
  fi
}

assert_body_matches() {
  local expected="$1"
  local label="$2"

  if grep -Eq "$expected" "$body_file"; then
    pass "$label"
  else
    fail "$label"
    printf '    missing body pattern: %s\n' "$expected" >&2
    sed 's/^/    body: /' "$body_file" >&2
  fi
}

assert_header_equals() {
  local header="$1"
  local expected="$2"
  local label="$3"
  local actual

  actual="$(header_value "$header")"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (expected $header: $expected, got: ${actual:-<missing>})"
  fi
}

assert_header_matches() {
  local header="$1"
  local expected="$2"
  local label="$3"
  local actual

  actual="$(header_value "$header")"
  if [[ "$actual" =~ $expected ]]; then
    pass "$label"
  else
    fail "$label (header $header was: ${actual:-<missing>})"
  fi
}

printf 'Using proxy=%s admin=%s status=%s\n' "$PROXY_URL" "$ADMIN_URL" "$STATUS_URL"

run_curl "Health - Kong status API is ready" \
  "$STATUS_URL/status"
assert_status "200" "status API returns 200"
assert_body_contains "{" "status body is JSON"

run_curl "Admin - Kong version is 3.4.2" \
  "$ADMIN_URL/"
assert_status "200" "Admin API returns 200"
assert_body_matches '"version"[[:space:]]*:[[:space:]]*"3\.4\.2"' "Kong version is 3.4.2"

run_curl "Admin - custom plugins are enabled" \
  "$ADMIN_URL/plugins/enabled"
assert_status "200" "enabled plugins endpoint returns 200"
assert_body_contains "request-profiler" "request-profiler is enabled"
assert_body_contains "json-field-guard" "json-field-guard is enabled"
assert_body_contains "canary-header-router" "canary-header-router is enabled"

run_curl "Proxy - request profiler adds correlation and timing" \
  -H "X-Request-Id: postman-request-profiler" \
  -H "X-User-Id: user-profiler" \
  "$PROXY_URL/anything/get"
assert_status "200" "proxy returns 200"
assert_header_matches "X-Kong-Elapsed" '^[0-9]+(\.[0-9]+)?ms$' "request-profiler response elapsed header is present"
assert_header_equals "X-Request-Id" "postman-request-profiler" "request-profiler echoes request ID"
assert_header_matches "X-Release-Decision" '^(stable|canary)$' "canary plugin annotates the response"
assert_body_contains '"method": "GET"' "upstream echo received GET"
assert_body_contains '"path": "/anything/get"' "upstream echo received the proxied path"
assert_body_contains "postman-request-profiler" "upstream echo received the request ID"

run_curl "Proxy - canary override forces canary" \
  -H "X-Canary-Override: canary" \
  -H "X-User-Id: user-canary" \
  "$PROXY_URL/anything/headers"
assert_status "200" "proxy returns 200"
assert_header_equals "X-Release-Decision" "canary" "response shows forced canary"
assert_header_equals "X-Release-Reason" "forced" "response explains forced canary"
assert_body_contains '"X-Release-Track": "canary"' "upstream received canary track header"

run_curl "Proxy - canary override forces stable" \
  -H "X-Canary-Override: stable" \
  -H "X-User-Id: user-stable" \
  "$PROXY_URL/anything/headers"
assert_status "200" "proxy returns 200"
assert_header_equals "X-Release-Decision" "stable" "response shows forced stable"
assert_header_equals "X-Release-Reason" "forced" "response explains forced stable"
assert_body_contains '"X-Release-Track": "stable"' "upstream received stable track header"

run_curl "JSON guard - valid payload is proxied" \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"customer_id":"cust-123","action":"signup"}' \
  "$PROXY_URL/guarded/post"
assert_status "200" "valid JSON is proxied"
assert_body_contains '"path": "/post"' "guard stripped /guarded"
assert_body_contains '"customer_id": "cust-123"' "upstream received customer_id"
assert_body_contains '"action": "signup"' "upstream received action"
assert_body_contains '"X-Json-Guard": "passed"' "upstream received guard pass header"

run_curl "JSON guard - missing required field is rejected" \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"customer_id":"cust-123"}' \
  "$PROXY_URL/guarded/post"
assert_status "422" "missing required field returns 422"
assert_body_contains "Required JSON fields are missing" "response names missing-field problem"
assert_body_contains "action" "response names the missing field"

run_curl "JSON guard - forbidden key is rejected" \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"customer_id":"cust-123","action":"signup","password":"secret"}' \
  "$PROXY_URL/guarded/post"
assert_status "422" "forbidden key returns 422"
assert_body_contains "Forbidden JSON fields are present" "response names forbidden-key problem"
assert_body_contains "password" "response names the forbidden key"

run_curl "JSON guard - non-JSON payload is rejected" \
  -X POST \
  -H "Content-Type: text/plain" \
  --data 'customer_id=cust-123&action=signup' \
  "$PROXY_URL/guarded/post"
assert_status "415" "non-JSON payload returns 415"
assert_body_contains "JSON payload required" "response explains that JSON is required"

printf '\nCurl summary: requests=%s assertions=%s failures=%s\n' "$requests" "$assertions" "$failures"

if (( failures > 0 )); then
  exit 1
fi
