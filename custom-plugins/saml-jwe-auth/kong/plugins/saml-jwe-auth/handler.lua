local cjson = require "cjson.safe"
local ffi = require "ffi"
local resty_sha256 = require "resty.sha256"


ffi.cdef[[
int kong_saml_random(unsigned char *out, size_t out_len, char *err, size_t err_len);

int kong_saml_deflate_raw(const unsigned char *input, size_t input_len,
  unsigned char *output, size_t output_len,
  size_t *actual_out_len,
  char *err, size_t err_len);

int kong_saml_aes_gcm_encrypt(const unsigned char *key, size_t key_len,
  const unsigned char *iv, size_t iv_len,
  const unsigned char *aad, size_t aad_len,
  const unsigned char *plaintext, size_t plaintext_len,
  unsigned char *ciphertext,
  unsigned char *tag, size_t tag_len,
  char *err, size_t err_len);

int kong_saml_aes_gcm_decrypt(const unsigned char *key, size_t key_len,
  const unsigned char *iv, size_t iv_len,
  const unsigned char *aad, size_t aad_len,
  const unsigned char *ciphertext, size_t ciphertext_len,
  const unsigned char *tag, size_t tag_len,
  unsigned char *plaintext,
  char *err, size_t err_len);

int kong_saml_validate_response(const char *xml, size_t xml_len,
  const char *cert_pem, size_t cert_len,
  const char *expected_issuer,
  const char *expected_audience,
  const char *expected_destination,
  const char *expected_recipient,
  long now,
  int skew,
  char *err,
  size_t err_len);

int kong_saml_extract(const char *xml, size_t xml_len,
  const char *selector,
  const char *name,
  char *out,
  size_t out_len,
  char *err,
  size_t err_len);
]]


local PLUGIN_NAME = "saml-jwe-auth"
local REPLAY_DICT = "kong_saml_jwe_auth_replay"
local MAX_ACS_FORM_BODY_BYTES = 5 * 1024 * 1024
local JWE_HEADER = cjson.encode({
  alg = "dir",
  enc = "A256GCM",
  typ = "JWT",
})


local SamlJweAuthHandler = {
  VERSION = "0.1.0",
  PRIORITY = 1005,
}


local native_lib
local native_load_err
local metadata_cert_cache = {}


local function get_native()
  if native_lib then
    return native_lib
  end

  if native_load_err then
    return nil, native_load_err
  end

  local ok, lib = pcall(ffi.load, "kong_saml_jwe_auth")
  if not ok then
    ok, lib = pcall(ffi.load, "libkong_saml_jwe_auth.so")
  end

  if not ok then
    native_load_err = tostring(lib)
    return nil, native_load_err
  end

  native_lib = lib
  return native_lib
end


local function errbuf()
  return ffi.new("char[512]"), 512
end


local function native_error(buf)
  local msg = ffi.string(buf)
  if msg == "" then
    return "native operation failed"
  end
  return msg
end


local function debug_log(conf, ...)
  if conf.debug_enabled then
    kong.log.notice("[saml-jwe-auth debug] ", ...)
  end
end


local function debug_log_value(conf, label, value, enabled)
  if not conf.debug_enabled or not enabled then
    return
  end

  value = tostring(value or "")
  local max_bytes = conf.debug_log_max_bytes or 4096
  local truncated = #value > max_bytes
  local display = truncated and value:sub(1, max_bytes) or value

  debug_log(conf, label, " bytes=", #value, " value=", display)

  if truncated then
    debug_log(conf, label, " truncated_bytes=", #value - max_bytes)
  end
end


local function safe_debug_filename_part(value)
  value = tostring(value or "")
  value = value:gsub("[^%w._-]", "_")

  if value == "" then
    return "unknown"
  end

  if #value > 96 then
    return value:sub(1, 96)
  end

  return value
end


local function debug_write_file(conf, filename, value)
  if not conf.debug_enabled then
    return nil
  end

  local dir = conf.debug_capture_dir
  if type(dir) ~= "string" or dir == "" then
    return nil
  end

  dir = dir:gsub("[/\\]+$", "")
  local path = dir .. "/" .. filename
  value = tostring(value or "")

  local file, open_err = io.open(path, "wb")
  if not file then
    debug_log(conf, "could not write debug capture file=", path, " error=", tostring(open_err))
    return nil
  end

  local ok, write_err = file:write(value)
  local close_ok, close_err = file:close()

  if not ok then
    debug_log(conf, "could not write debug capture file=", path, " error=", tostring(write_err))
    return nil
  end

  if not close_ok then
    debug_log(conf, "could not close debug capture file=", path, " error=", tostring(close_err))
    return nil
  end

  debug_log(conf, "wrote debug capture file=", path, " bytes=", #value)
  return path
end


local function debug_capture_saml(conf, relay, saml_response, relay_state, xml)
  if not conf.debug_enabled then
    return
  end

  local dir = conf.debug_capture_dir
  if type(dir) ~= "string" or dir == "" then
    return
  end

  local request_id = relay and relay.request_id or "unknown"
  local prefix = os.date("!%Y%m%dT%H%M%SZ", ngx.time())
      .. "_"
      .. safe_debug_filename_part(request_id)

  local b64_path = debug_write_file(conf, prefix .. "_saml-response.b64", saml_response)
  local xml_path = debug_write_file(conf, prefix .. "_saml-response.xml", xml)
  local relay_path = debug_write_file(conf, prefix .. "_relay-state.txt", relay_state)

  local manifest = cjson.encode({
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ", ngx.time()),
    request_id = request_id,
    saml_response_b64_bytes = #(saml_response or ""),
    saml_response_xml_bytes = #(xml or ""),
    relay_state_bytes = #(relay_state or ""),
    saml_response_b64_file = b64_path,
    saml_response_xml_file = xml_path,
    relay_state_file = relay_path,
  })

  debug_write_file(conf, prefix .. "_manifest.json", manifest or "{}")
end


local function debug_capture_saml_request(conf, request_id, binding, saml_request, relay_state, xml)
  if not conf.debug_enabled or not conf.debug_log_saml_request then
    return
  end

  local dir = conf.debug_capture_dir
  if type(dir) ~= "string" or dir == "" then
    return
  end

  local safe_binding = safe_debug_filename_part(binding)
  local prefix = os.date("!%Y%m%dT%H%M%SZ", ngx.time())
      .. "_"
      .. safe_debug_filename_part(request_id)

  local b64_path = debug_write_file(conf, prefix .. "_saml-request-" .. safe_binding .. ".b64", saml_request)
  local xml_path = debug_write_file(conf, prefix .. "_saml-request.xml", xml)
  local relay_path = debug_write_file(conf, prefix .. "_relay-state.txt", relay_state)

  local manifest = cjson.encode({
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ", ngx.time()),
    request_id = request_id,
    binding = binding,
    saml_request_b64_bytes = #(saml_request or ""),
    saml_request_xml_bytes = #(xml or ""),
    relay_state_bytes = #(relay_state or ""),
    saml_request_b64_file = b64_path,
    saml_request_xml_file = xml_path,
    relay_state_file = relay_path,
  })

  debug_write_file(conf, prefix .. "_saml-request-manifest.json", manifest or "{}")
end


local function base64url_encode(value)
  return (ngx.encode_base64(value):gsub("+", "-"):gsub("/", "_"):gsub("=", ""))
end


local function base64url_decode(value)
  if not value then
    return nil
  end

  local normalized = value:gsub("-", "+"):gsub("_", "/")
  local pad = #normalized % 4
  if pad == 2 then
    normalized = normalized .. "=="
  elseif pad == 3 then
    normalized = normalized .. "="
  elseif pad ~= 0 then
    return nil
  end

  return ngx.decode_base64(normalized)
end


local function xml_escape(value)
  value = tostring(value or "")
  value = value:gsub("&", "&amp;")
  value = value:gsub("<", "&lt;")
  value = value:gsub(">", "&gt;")
  value = value:gsub("\"", "&quot;")
  value = value:gsub("'", "&apos;")
  return value
end


local function html_escape(value)
  return xml_escape(value)
end


local function normalize_key(raw)
  if #raw == 32 then
    return raw
  end

  local sha256 = resty_sha256:new()
  sha256:update(raw)
  return sha256:final()
end


local function random_bytes(len)
  local lib, load_err = get_native()
  if not lib then
    return nil, "could not load native SAML library: " .. load_err
  end

  local out = ffi.new("unsigned char[?]", len)
  local err, err_len = errbuf()
  if lib.kong_saml_random(out, len, err, err_len) ~= 0 then
    return nil, native_error(err)
  end

  return ffi.string(out, len)
end


local function random_id()
  local bytes, err = random_bytes(24)
  if not bytes then
    return nil, err
  end

  return "_" .. base64url_encode(bytes)
end


local function deflate_raw(value)
  local lib, load_err = get_native()
  if not lib then
    return nil, "could not load native SAML library: " .. load_err
  end

  local out_len = (#value * 2) + 256
  local out = ffi.new("unsigned char[?]", out_len)
  local actual = ffi.new("size_t[1]")
  local err, err_len = errbuf()

  if lib.kong_saml_deflate_raw(value, #value, out, out_len, actual, err, err_len) ~= 0 then
    return nil, native_error(err)
  end

  return ffi.string(out, tonumber(actual[0]))
end


local function pem_from_base64_cert(cert)
  cert = (cert or ""):gsub("%s+", "")
  if cert == "" then
    return nil
  end

  local lines = {}
  for i = 1, #cert, 64 do
    lines[#lines + 1] = cert:sub(i, i + 63)
  end

  return "-----BEGIN CERTIFICATE-----\n"
      .. table.concat(lines, "\n")
      .. "\n-----END CERTIFICATE-----"
end


local function extract_metadata_cert(metadata)
  if not metadata then
    return nil
  end

  local cert = metadata:match("<[%w_%-]*:?X509Certificate[^>]*>(.-)</[%w_%-]*:?X509Certificate>")
  return pem_from_base64_cert(cert)
end


local function get_idp_certificate(conf)
  if conf.idp_certificate_pem and conf.idp_certificate_pem ~= "" then
    return conf.idp_certificate_pem
  end

  if not conf.idp_metadata_url or conf.idp_metadata_url == "" then
    return nil, "either idp_certificate_pem or idp_metadata_url must be configured"
  end

  local cached = metadata_cert_cache[conf.idp_metadata_url]
  if cached and cached.expires_at > ngx.time() then
    return cached.pem
  end

  local http = require "resty.http"
  local httpc = http.new()
  httpc:set_timeout(5000)

  local res, err = httpc:request_uri(conf.idp_metadata_url, {
    method = "GET",
    ssl_verify = true,
  })

  if not res then
    return nil, "could not fetch IdP metadata: " .. tostring(err)
  end

  if res.status ~= 200 then
    return nil, "IdP metadata returned HTTP " .. tostring(res.status)
  end

  local pem = extract_metadata_cert(res.body)
  if not pem then
    return nil, "IdP metadata did not contain a signing certificate"
  end

  metadata_cert_cache[conf.idp_metadata_url] = {
    pem = pem,
    expires_at = ngx.time() + 300,
  }

  return pem
end


local function encrypt_jwe(conf, claims)
  local lib, load_err = get_native()
  if not lib then
    return nil, "could not load native SAML library: " .. load_err
  end

  local plaintext = cjson.encode(claims)
  if not plaintext then
    return nil, "could not encode JWE payload"
  end

  local protected = base64url_encode(JWE_HEADER)
  local key = normalize_key(conf.jwe_key)
  local iv, random_err = random_bytes(12)
  if not iv then
    return nil, random_err
  end

  local ciphertext = ffi.new("unsigned char[?]", #plaintext)
  local tag = ffi.new("unsigned char[16]")
  local err, err_len = errbuf()

  local rc = lib.kong_saml_aes_gcm_encrypt(
      key, #key,
      iv, #iv,
      protected, #protected,
      plaintext, #plaintext,
      ciphertext,
      tag, 16,
      err, err_len)

  if rc ~= 0 then
    return nil, native_error(err)
  end

  return protected
      .. ".."
      .. base64url_encode(iv)
      .. "."
      .. base64url_encode(ffi.string(ciphertext, #plaintext))
      .. "."
      .. base64url_encode(ffi.string(tag, 16))
end


local function decrypt_jwe(conf, token)
  local protected, encrypted_key, iv_b64, ciphertext_b64, tag_b64 =
      token:match("^([^.]+)%.([^.]*)%.([^.]+)%.([^.]+)%.([^.]+)$")

  if not protected then
    return nil, "invalid JWE compact serialization"
  end

  if encrypted_key ~= "" then
    return nil, "only direct JWE encryption is supported"
  end

  local header_json = base64url_decode(protected)
  if not header_json then
    return nil, "invalid JWE protected header"
  end

  local header = cjson.decode(header_json)
  if not header or header.alg ~= "dir" or header.enc ~= "A256GCM" then
    return nil, "unsupported JWE header"
  end

  local iv = base64url_decode(iv_b64)
  local ciphertext = base64url_decode(ciphertext_b64)
  local tag = base64url_decode(tag_b64)

  if not iv or not ciphertext or not tag then
    return nil, "invalid JWE encoding"
  end

  if #iv ~= 12 or #tag ~= 16 then
    return nil, "invalid JWE IV or tag length"
  end

  local lib, load_err = get_native()
  if not lib then
    return nil, "could not load native SAML library: " .. load_err
  end

  local key = normalize_key(conf.jwe_key)
  local plaintext = ffi.new("unsigned char[?]", #ciphertext)
  local err, err_len = errbuf()

  local rc = lib.kong_saml_aes_gcm_decrypt(
      key, #key,
      iv, #iv,
      protected, #protected,
      ciphertext, #ciphertext,
      tag, #tag,
      plaintext,
      err, err_len)

  if rc ~= 0 then
    return nil, native_error(err)
  end

  local claims = cjson.decode(ffi.string(plaintext, #ciphertext))
  if not claims then
    return nil, "invalid JWE payload"
  end

  local now = ngx.time()
  if claims.exp and tonumber(claims.exp) and now >= tonumber(claims.exp) then
    return nil, "JWE has expired"
  end

  return claims
end


local function extract_bearer_token(conf)
  local token_header = kong.request.get_header(conf.token_header)
  if token_header then
    local bearer = token_header:match("^[Bb]earer%s+(.+)$")
    if bearer and bearer ~= "" then
      return bearer
    end
  end

  if kong.request.get_cookie then
    return kong.request.get_cookie(conf.session_cookie_name)
  end

  local cookie = kong.request.get_header("Cookie")
  if not cookie then
    return nil
  end

  for chunk in cookie:gmatch("[^;]+") do
    local name, value = chunk:match("^%s*([^=]+)=?(.*)$")
    if name == conf.session_cookie_name then
      return value
    end
  end

  return nil
end


local function authenticated_claims(conf)
  local token = extract_bearer_token(conf)
  if not token or token == "" then
    return nil
  end

  return decrypt_jwe(conf, token)
end


local function request_uri()
  local uri = ngx.var.request_uri
  if uri and uri ~= "" then
    return uri
  end

  return kong.request.get_path()
end


local function safe_return_to(value)
  if type(value) ~= "string" or value == "" then
    return "/"
  end

  if value:find("[\r\n]", 1, false) then
    return "/"
  end

  if value:sub(1, 1) ~= "/" or value:sub(1, 2) == "//" then
    return "/"
  end

  return value
end


local function utc_timestamp(epoch)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end


local function build_authn_request(conf, request_id)
  local now = utc_timestamp(ngx.time())

  return table.concat({
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    "<samlp:AuthnRequest xmlns:samlp=\"urn:oasis:names:tc:SAML:2.0:protocol\"",
    " xmlns:saml=\"urn:oasis:names:tc:SAML:2.0:assertion\"",
    " ID=\"", xml_escape(request_id), "\"",
    " Version=\"2.0\"",
    " IssueInstant=\"", xml_escape(now), "\"",
    " Destination=\"", xml_escape(conf.idp_sso_url), "\"",
    " AssertionConsumerServiceURL=\"", xml_escape(conf.assertion_consumer_service_url), "\"",
    " ProtocolBinding=\"urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST\">",
    "<saml:Issuer>", xml_escape(conf.sp_entity_id), "</saml:Issuer>",
    "<samlp:NameIDPolicy Format=\"", xml_escape(conf.name_id_format), "\" AllowCreate=\"true\"/>",
    "</samlp:AuthnRequest>",
  })
end


local function auto_post_form(action, saml_request, relay_state)
  return table.concat({
    "<!doctype html><html><head><meta charset=\"utf-8\"><title>SAML sign in</title></head>",
    "<body><form method=\"post\" action=\"", html_escape(action), "\">",
    "<input type=\"hidden\" name=\"SAMLRequest\" value=\"", html_escape(saml_request), "\">",
    "<input type=\"hidden\" name=\"RelayState\" value=\"", html_escape(relay_state), "\">",
    "<noscript><button type=\"submit\">Continue</button></noscript>",
    "</form><script>document.forms[0].submit();</script></body></html>",
  })
end


local function append_query(url, params)
  local sep = url:find("?", 1, true) and "&" or "?"
  return url .. sep .. table.concat(params, "&")
end


local function start_login(conf)
  local request_id, id_err = random_id()
  if not request_id then
    return kong.response.exit(500, { message = id_err })
  end

  local now = ngx.time()
  local return_to = safe_return_to(request_uri())
  local relay, relay_err = encrypt_jwe(conf, {
    typ = "saml-relay",
    request_id = request_id,
    return_to = return_to,
    iat = now,
    exp = now + conf.relay_state_ttl_seconds,
  })

  if not relay then
    return kong.response.exit(500, { message = relay_err })
  end

  local request_xml = build_authn_request(conf, request_id)
  local deflated, deflate_err = deflate_raw(request_xml)
  if not deflated then
    return kong.response.exit(500, { message = deflate_err })
  end
  local request_b64 = ngx.encode_base64(deflated)

  debug_log(conf,
      "starting SAML login request_id=", request_id,
      " return_to=", return_to,
      " acs=", conf.assertion_consumer_service_url,
      " idp_sso_url=", conf.idp_sso_url)
  debug_log_value(conf, "SAMLRequest Redirect value", request_b64, conf.debug_log_saml_request)
  debug_log_value(conf, "AuthnRequest XML", request_xml, conf.debug_log_saml_request)
  debug_capture_saml_request(conf, request_id, "redirect", request_b64, relay, request_xml)

  local location = append_query(conf.idp_sso_url, {
    "SAMLRequest=" .. ngx.escape_uri(request_b64),
    "RelayState=" .. ngx.escape_uri(relay),
  })

  return kong.response.exit(302, nil, {
    ["Location"] = location,
    ["Cache-Control"] = "no-store",
  })
end


local function start_login_post(conf)
  local request_id, id_err = random_id()
  if not request_id then
    return kong.response.exit(500, { message = id_err })
  end

  local now = ngx.time()
  local return_to = safe_return_to(request_uri())
  local relay, relay_err = encrypt_jwe(conf, {
    typ = "saml-relay",
    request_id = request_id,
    return_to = return_to,
    iat = now,
    exp = now + conf.relay_state_ttl_seconds,
  })

  if not relay then
    return kong.response.exit(500, { message = relay_err })
  end

  local request_xml = build_authn_request(conf, request_id)
  local request_b64 = ngx.encode_base64(request_xml)
  local html = auto_post_form(conf.idp_sso_url, request_b64, relay)

  debug_log(conf,
      "starting SAML POST login request_id=", request_id,
      " return_to=", return_to,
      " acs=", conf.assertion_consumer_service_url,
      " idp_sso_url=", conf.idp_sso_url)
  debug_log_value(conf, "SAMLRequest POST value", request_b64, conf.debug_log_saml_request)
  debug_log_value(conf, "AuthnRequest XML", request_xml, conf.debug_log_saml_request)
  debug_capture_saml_request(conf, request_id, "post", request_b64, relay, request_xml)

  return kong.response.exit(200, html, {
    ["Content-Type"] = "text/html; charset=utf-8",
    ["Cache-Control"] = "no-store",
  })
end


local function extract_from_saml(xml, selector, name)
  local lib, load_err = get_native()
  if not lib then
    return nil, "could not load native SAML library: " .. load_err
  end

  local out = ffi.new("char[4096]")
  local err, err_len = errbuf()
  local rc = lib.kong_saml_extract(xml, #xml, selector, name or "", out, 4096, err, err_len)
  if rc ~= 0 then
    return nil, native_error(err)
  end

  local value = ffi.string(out)
  if value == "" then
    return nil
  end

  return value
end


local function validate_saml_response(conf, xml)
  local lib, load_err = get_native()
  if not lib then
    return nil, "could not load native SAML library: " .. load_err
  end

  local certificate_pem, cert_err = get_idp_certificate(conf)
  if not certificate_pem then
    return nil, cert_err
  end

  local err, err_len = errbuf()
  local rc = lib.kong_saml_validate_response(
      xml, #xml,
      certificate_pem, #certificate_pem,
      conf.idp_entity_id,
      conf.sp_entity_id,
      conf.assertion_consumer_service_url,
      conf.assertion_consumer_service_url,
      ngx.time(),
      conf.clock_skew_seconds,
      err, err_len)

  if rc ~= 0 then
    return nil, native_error(err)
  end

  return true
end


local function remember_assertion(conf, assertion_id)
  if not conf.require_replay_protection then
    return true
  end

  if not assertion_id or assertion_id == "" then
    return nil, "SAML assertion did not contain an ID for replay protection"
  end

  local dict = ngx.shared[REPLAY_DICT]
  if not dict then
    return nil, "missing lua_shared_dict " .. REPLAY_DICT
  end

  local ok, err = dict:safe_add(assertion_id, true, conf.session_ttl_seconds)
  if ok then
    return true
  end

  if err == "exists" then
    return nil, "SAML assertion replay detected"
  end

  return nil, "could not record SAML assertion ID: " .. tostring(err)
end


local function cookie_header(conf, token)
  local parts = {
    conf.session_cookie_name .. "=" .. token,
    "Path=/",
    "HttpOnly",
    "Max-Age=" .. tostring(conf.session_ttl_seconds),
    "SameSite=" .. conf.session_cookie_same_site,
  }

  if conf.session_cookie_secure then
    parts[#parts + 1] = "Secure"
  end

  return table.concat(parts, "; ")
end


local function read_request_body(max_bytes)
  ngx.req.read_body()

  local data = ngx.req.get_body_data()
  if data then
    if #data > max_bytes then
      return nil, "request body too large"
    end
    return data
  end

  local body_file = ngx.req.get_body_file()
  if not body_file then
    return ""
  end

  local file, open_err = io.open(body_file, "rb")
  if not file then
    return nil, "could not open request body temp file: " .. tostring(open_err)
  end

  local size = file:seek("end")
  if size and size > max_bytes then
    file:close()
    return nil, "request body too large"
  end

  file:seek("set")
  local body = file:read("*a")
  file:close()

  return body or ""
end


local function read_form_body()
  local raw_body, read_err = read_request_body(MAX_ACS_FORM_BODY_BYTES)
  if not raw_body then
    return nil, read_err
  end

  local args, decode_err = ngx.decode_args(raw_body, 100)
  if not args then
    return nil, "could not decode SAML POST form body: " .. tostring(decode_err)
  end

  return args
end


local function handle_acs(conf)
  if kong.request.get_method() ~= "POST" then
    return kong.response.exit(405, { message = "SAML ACS requires POST" })
  end

  local body, body_err = read_form_body()
  if not body then
    return kong.response.exit(400, { message = "could not read SAML POST body", detail = body_err })
  end

  local saml_response = body.SAMLResponse
  local relay_state = body.RelayState

  if not saml_response or saml_response == "" then
    return kong.response.exit(400, { message = "missing SAMLResponse" })
  end

  if not relay_state or relay_state == "" then
    return kong.response.exit(400, { message = "missing RelayState" })
  end

  debug_log(conf,
      "received ACS POST saml_response_b64_bytes=", #saml_response,
      " relay_state_bytes=", #relay_state)
  debug_log_value(conf, "SAMLResponse POST value", saml_response, conf.debug_log_saml_response)

  local relay, relay_err = decrypt_jwe(conf, relay_state)
  if not relay or relay.typ ~= "saml-relay" then
    return kong.response.exit(400, { message = "invalid RelayState", detail = relay_err })
  end

  local xml = ngx.decode_base64(saml_response)
  if not xml then
    return kong.response.exit(400, { message = "invalid SAMLResponse encoding" })
  end

  debug_log(conf, "decoded SAMLResponse XML bytes=", #xml)
  debug_log_value(conf, "decoded SAMLResponse XML", xml, conf.debug_log_saml_response)
  debug_capture_saml(conf, relay, saml_response, relay_state, xml)

  local ok, validate_err = validate_saml_response(conf, xml)
  if not ok then
    kong.log.warn("SAML response validation failed: ", validate_err)
    return kong.response.exit(401, { message = "invalid SAMLResponse" })
  end

  debug_log(conf, "SAML response signature and conditions validated")

  local in_response_to = extract_from_saml(xml, "response_in_response_to")
  debug_log(conf,
      "SAML InResponseTo=", tostring(in_response_to),
      " relay_request_id=", tostring(relay.request_id))
  if in_response_to ~= relay.request_id then
    return kong.response.exit(401, { message = "SAML response did not match RelayState request" })
  end

  local assertion_id = extract_from_saml(xml, "assertion_id")
  debug_log(conf, "SAML assertion_id=", tostring(assertion_id))
  local remembered, replay_err = remember_assertion(conf, assertion_id)
  if not remembered then
    return kong.response.exit(401, { message = replay_err })
  end

  local subject = extract_from_saml(xml, "nameid") or ""
  debug_log(conf, "SAML subject=", subject)
  if subject == "" then
    return kong.response.exit(401, { message = "SAML assertion did not contain a NameID" })
  end

  local attrs = {}
  for _, mapping in ipairs(conf.attribute_mappings or {}) do
    local value = extract_from_saml(xml, "attribute", mapping.saml_attribute)
    if value then
      attrs[mapping.claim] = value
    end
  end

  debug_log(conf, "SAML attributes=", cjson.encode(attrs) or "{}")

  local now = ngx.time()
  local session_token, token_err = encrypt_jwe(conf, {
    typ = "saml-session",
    iss = PLUGIN_NAME,
    sub = subject,
    attrs = attrs,
    iat = now,
    exp = now + conf.session_ttl_seconds,
  })

  if not session_token then
    return kong.response.exit(500, { message = token_err })
  end

  debug_log(conf,
      "issued SAML JWE session subject=", subject,
      " return_to=", safe_return_to(relay.return_to))

  return kong.response.exit(302, nil, {
    ["Location"] = safe_return_to(relay.return_to),
    ["Set-Cookie"] = cookie_header(conf, session_token),
    ["Cache-Control"] = "no-store",
  })
end


local function path_matches(path, configured)
  if path == configured then
    return true
  end

  if configured ~= "/" and path == configured .. "/" then
    return true
  end

  return false
end


function SamlJweAuthHandler:rewrite(conf)
  if conf.allow_unauthenticated_options and kong.request.get_method() == "OPTIONS" then
    return
  end

  local path = kong.request.get_path()
  if path_matches(path, conf.acs_path) then
    return handle_acs(conf)
  end

  local claims = authenticated_claims(conf)
  if claims then
    kong.ctx.plugin.claims = claims
    return
  end

  return start_login(conf)
end


function SamlJweAuthHandler:access(conf)
  if conf.allow_unauthenticated_options and kong.request.get_method() == "OPTIONS" then
    return
  end

  local path = kong.request.get_path()
  if path_matches(path, conf.acs_path) then
    return handle_acs(conf)
  end

  local claims = kong.ctx.plugin.claims
  if not claims then
    claims = authenticated_claims(conf)
  end

  if not claims then
    return start_login(conf)
  end

  kong.service.request.set_header(conf.upstream_subject_header, claims.sub)

  for _, mapping in ipairs(conf.attribute_mappings or {}) do
    if mapping.upstream_header and claims.attrs and claims.attrs[mapping.claim] then
      kong.service.request.set_header(mapping.upstream_header, tostring(claims.attrs[mapping.claim]))
    end
  end
end


return SamlJweAuthHandler
