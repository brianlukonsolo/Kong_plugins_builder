local typedefs = require "kong.db.schema.typedefs"


return {
  name = "canary-header-router",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { percentage = {
              type = "integer",
              default = 10,
              between = { 0, 100 },
            },
          },
          { stickiness_header = {
              type = "string",
              default = "X-User-Id",
              len_min = 1,
            },
          },
          { force_header = {
              type = "string",
              default = "X-Canary-Override",
              len_min = 1,
            },
          },
          { force_canary_value = {
              type = "string",
              default = "canary",
              len_min = 1,
            },
          },
          { force_stable_value = {
              type = "string",
              default = "stable",
              len_min = 1,
            },
          },
          { upstream_header = {
              type = "string",
              default = "X-Release-Track",
              len_min = 1,
            },
          },
          { canary_value = {
              type = "string",
              default = "canary",
              len_min = 1,
            },
          },
          { stable_value = {
              type = "string",
              default = "stable",
              len_min = 1,
            },
          },
          { bucket_header = {
              type = "string",
              default = "X-Release-Bucket",
              len_min = 1,
            },
          },
          { response_header = {
              type = "string",
              default = "X-Release-Decision",
              len_min = 1,
            },
          },
          { reason_header = {
              type = "string",
              default = "X-Release-Reason",
              len_min = 1,
            },
          },
        },
      },
    },
  },
}
