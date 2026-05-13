local cjson = require "cjson.safe"


local RequestProfilerHandler = {
  VERSION = "0.1.0",
  PRIORITY = 900,
}


local function fallback_request_id()
  if kong.request.get_id then
    local id = kong.request.get_id()
    if id and id ~= "" then
      return id
    end
  end

  return ngx.var.request_id
      or (tostring(ngx.var.connection or "conn") .. "-" .. tostring(ngx.var.connection_requests or "0"))
end


function RequestProfilerHandler:access(conf)
  local request_id = kong.request.get_header(conf.request_header)

  if not request_id or request_id == "" then
    request_id = fallback_request_id()
  end

  kong.ctx.plugin.started_at = ngx.now()
  kong.ctx.plugin.request_id = request_id

  kong.service.request.set_header(conf.request_header, request_id)
end


function RequestProfilerHandler:header_filter(conf)
  local started_at = kong.ctx.plugin.started_at

  if started_at then
    local elapsed_ms = (ngx.now() - started_at) * 1000
    kong.response.set_header(conf.response_time_header, string.format("%.2fms", elapsed_ms))
  end

  if conf.echo_request_id and kong.ctx.plugin.request_id then
    kong.response.set_header(conf.request_header, kong.ctx.plugin.request_id)
  end
end


function RequestProfilerHandler:log(conf)
  if not conf.log_summary then
    return
  end

  local started_at = kong.ctx.plugin.started_at
  local elapsed_ms = started_at and ((ngx.now() - started_at) * 1000) or nil

  local summary = {
    request_id = kong.ctx.plugin.request_id,
    method = kong.request.get_method(),
    path = kong.request.get_path(),
    status = kong.response.get_status(),
    elapsed_ms = elapsed_ms and tonumber(string.format("%.2f", elapsed_ms)) or nil,
  }

  kong.log.notice("request-profiler summary: ", cjson.encode(summary))
end


return RequestProfilerHandler
