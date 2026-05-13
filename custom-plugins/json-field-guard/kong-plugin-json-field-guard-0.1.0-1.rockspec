package = "kong-plugin-json-field-guard"
version = "0.1.0-1"

source = {
  url = ".",
}

description = {
  summary = "Kong plugin that validates JSON request bodies before proxying.",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.json-field-guard.handler"] = "kong/plugins/json-field-guard/handler.lua",
    ["kong.plugins.json-field-guard.schema"] = "kong/plugins/json-field-guard/schema.lua",
  },
}
