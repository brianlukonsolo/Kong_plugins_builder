package = "kong-plugin-canary-header-router"
version = "0.1.0-1"

source = {
  url = ".",
}

description = {
  summary = "Kong plugin that assigns requests to stable or canary release tracks.",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.canary-header-router.handler"] = "kong/plugins/canary-header-router/handler.lua",
    ["kong.plugins.canary-header-router.schema"] = "kong/plugins/canary-header-router/schema.lua",
  },
}
