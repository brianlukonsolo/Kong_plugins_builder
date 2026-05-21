package = "kong-plugin-saml-jwe-auth"
version = "0.1.0-1"

source = {
  url = ".",
}

description = {
  summary = "Kong plugin that performs SAML browser SSO and issues encrypted JWE sessions.",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.saml-jwe-auth.handler"] = "kong/plugins/saml-jwe-auth/handler.lua",
    ["kong.plugins.saml-jwe-auth.schema"] = "kong/plugins/saml-jwe-auth/schema.lua",
  },
}
