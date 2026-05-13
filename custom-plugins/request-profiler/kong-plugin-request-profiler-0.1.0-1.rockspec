package = "kong-plugin-request-profiler"
version = "0.1.0-1"

source = {
  url = ".",
}

description = {
  summary = "Kong plugin that adds request correlation and timing headers.",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.request-profiler.handler"] = "kong/plugins/request-profiler/handler.lua",
    ["kong.plugins.request-profiler.schema"] = "kong/plugins/request-profiler/schema.lua",
  },
}
