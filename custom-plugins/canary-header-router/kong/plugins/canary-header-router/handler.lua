local CanaryHeaderRouterHandler = {
  VERSION = "0.1.0",
  PRIORITY = 800,
}


local function first_non_empty(...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if value and value ~= "" then
      return value
    end
  end

  return nil
end


local function canary_decision(conf)
  local override = kong.request.get_header(conf.force_header)
  if override == conf.force_canary_value then
    return true, "forced", nil
  end

  if override == conf.force_stable_value then
    return false, "forced", nil
  end

  local seed = first_non_empty(
    kong.request.get_header(conf.stickiness_header),
    kong.request.get_header("x-forwarded-for"),
    kong.client.get_forwarded_ip(),
    kong.request.get_path()
  )

  local bucket = ngx.crc32_short(seed or "kong") % 100
  return bucket < conf.percentage, "bucket", bucket
end


function CanaryHeaderRouterHandler:access(conf)
  local is_canary, reason, bucket = canary_decision(conf)
  local track = is_canary and conf.canary_value or conf.stable_value

  kong.ctx.plugin.track = track
  kong.ctx.plugin.reason = reason
  kong.ctx.plugin.bucket = bucket

  kong.service.request.set_header(conf.upstream_header, track)

  if bucket ~= nil then
    kong.service.request.set_header(conf.bucket_header, tostring(bucket))
  end
end


function CanaryHeaderRouterHandler:header_filter(conf)
  if kong.ctx.plugin.track then
    kong.response.set_header(conf.response_header, kong.ctx.plugin.track)
    kong.response.set_header(conf.reason_header, kong.ctx.plugin.reason)
  end

  if kong.ctx.plugin.bucket ~= nil then
    kong.response.set_header(conf.bucket_header, tostring(kong.ctx.plugin.bucket))
  end
end


return CanaryHeaderRouterHandler
