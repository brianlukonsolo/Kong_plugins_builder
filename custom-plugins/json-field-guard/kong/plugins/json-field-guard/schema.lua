local typedefs = require "kong.db.schema.typedefs"


return {
  name = "json-field-guard",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { methods = {
              type = "array",
              default = { "POST", "PUT", "PATCH" },
              elements = {
                type = "string",
                one_of = { "POST", "PUT", "PATCH" },
              },
            },
          },
          { required_fields = {
              type = "array",
              default = {},
              elements = {
                type = "string",
                len_min = 1,
              },
            },
          },
          { forbidden_keys = {
              type = "array",
              default = {},
              elements = {
                type = "string",
                len_min = 1,
              },
            },
          },
          { max_payload_bytes = {
              type = "integer",
              default = 32768,
              between = { 1, 1048576 },
            },
          },
          { require_json = {
              type = "boolean",
              default = true,
            },
          },
          { upstream_status_header = {
              type = "string",
              default = "X-Json-Guard",
              len_min = 1,
            },
          },
        },
      },
    },
  },
}
