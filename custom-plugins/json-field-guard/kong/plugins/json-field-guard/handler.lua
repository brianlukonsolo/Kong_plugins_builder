local cjson = require "cjson.safe"


local JsonFieldGuardHandler = {
  VERSION = "0.1.0",
  PRIORITY = 1100,
}


local function contains(list, value)
  for _, item in ipairs(list or {}) do
    if tostring(item):upper() == value then
      return true
    end
  end

  return false
end


local function build_lookup(list)
  local lookup = {}

  for _, item in ipairs(list or {}) do
    lookup[tostring(item)] = true
  end

  return lookup
end


local function missing_required_fields(payload, fields)
  local missing = {}

  for _, field in ipairs(fields or {}) do
    if payload[field] == nil then
      missing[#missing + 1] = field
    end
  end

  return missing
end


local function find_forbidden_keys(value, forbidden, path, hits)
  if type(value) ~= "table" then
    return hits
  end

  for key, child in pairs(value) do
    local key_text = tostring(key)
    local child_path = path == "" and key_text or (path .. "." .. key_text)

    if forbidden[key_text] then
      hits[#hits + 1] = child_path
    end

    find_forbidden_keys(child, forbidden, child_path, hits)
  end

  return hits
end


function JsonFieldGuardHandler:access(conf)
  local method = kong.request.get_method()
  if not contains(conf.methods, method) then
    return
  end

  local content_type = kong.request.get_header("content-type") or ""
  local is_json = content_type:lower():find("application/json", 1, true) ~= nil

  if not is_json then
    if conf.require_json then
      return kong.response.exit(415, {
        message = "JSON payload required",
      })
    end

    return
  end

  local body, err = kong.request.get_raw_body()
  if err then
    return kong.response.exit(400, {
      message = "Could not read request body",
      error = err,
    })
  end

  if not body or body == "" then
    return kong.response.exit(400, {
      message = "JSON payload required",
    })
  end

  if #body > conf.max_payload_bytes then
    return kong.response.exit(413, {
      message = "JSON payload too large",
      max_payload_bytes = conf.max_payload_bytes,
    })
  end

  local payload, decode_err = cjson.decode(body)
  if type(payload) ~= "table" then
    return kong.response.exit(400, {
      message = "Invalid JSON payload",
      error = decode_err,
    })
  end

  local missing = missing_required_fields(payload, conf.required_fields)
  if #missing > 0 then
    return kong.response.exit(422, {
      message = "Required JSON fields are missing",
      missing = missing,
    })
  end

  local forbidden = build_lookup(conf.forbidden_keys)
  local blocked = find_forbidden_keys(payload, forbidden, "", {})
  if #blocked > 0 then
    return kong.response.exit(422, {
      message = "Forbidden JSON fields are present",
      forbidden = blocked,
    })
  end

  kong.service.request.set_header(conf.upstream_status_header, "passed")
end


return JsonFieldGuardHandler
