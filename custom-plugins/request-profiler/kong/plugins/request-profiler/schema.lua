local typedefs = require "kong.db.schema.typedefs"


return {
  name = "request-profiler",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { request_header = {
              type = "string",
              default = "X-Request-Id",
              len_min = 1,
            },
          },
          { response_time_header = {
              type = "string",
              default = "X-Kong-Elapsed",
              len_min = 1,
            },
          },
          { echo_request_id = {
              type = "boolean",
              default = true,
            },
          },
          { log_summary = {
              type = "boolean",
              default = true,
            },
          },
        },
      },
    },
  },
}
