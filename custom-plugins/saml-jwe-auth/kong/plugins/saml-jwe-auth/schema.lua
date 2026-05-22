local typedefs = require "kong.db.schema.typedefs"


return {
  name = "saml-jwe-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { acs_path = {
              type = "string",
              default = "/auth",
              len_min = 1,
            },
          },
          { idp_sso_url = {
              type = "string",
              required = true,
              len_min = 1,
            },
          },
          { idp_entity_id = {
              type = "string",
              required = true,
              len_min = 1,
            },
          },
          { sp_entity_id = {
              type = "string",
              required = true,
              len_min = 1,
            },
          },
          { assertion_consumer_service_url = {
              type = "string",
              required = true,
              len_min = 1,
            },
          },
          { idp_certificate_pem = {
              type = "string",
              required = false,
              len_min = 1,
            },
          },
          { idp_metadata_url = {
              type = "string",
              required = false,
              len_min = 1,
            },
          },
          { jwe_key = {
              type = "string",
              required = true,
              len_min = 32,
            },
          },
          { session_cookie_name = {
              type = "string",
              default = "kong_saml_session",
              len_min = 1,
            },
          },
          { session_cookie_secure = {
              type = "boolean",
              default = false,
            },
          },
          { session_cookie_same_site = {
              type = "string",
              default = "Lax",
              one_of = { "Lax", "Strict", "None" },
            },
          },
          { session_ttl_seconds = {
              type = "integer",
              default = 3600,
              between = { 60, 86400 },
            },
          },
          { relay_state_ttl_seconds = {
              type = "integer",
              default = 300,
              between = { 30, 3600 },
            },
          },
          { clock_skew_seconds = {
              type = "integer",
              default = 120,
              between = { 0, 600 },
            },
          },
          { name_id_format = {
              type = "string",
              default = "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified",
              len_min = 1,
            },
          },
          { token_header = {
              type = "string",
              default = "Authorization",
              len_min = 1,
            },
          },
          { upstream_subject_header = {
              type = "string",
              default = "X-Authenticated-User",
              len_min = 1,
            },
          },
          { require_replay_protection = {
              type = "boolean",
              default = true,
            },
          },
          { allow_unauthenticated_options = {
              type = "boolean",
              default = true,
            },
          },
          { debug_enabled = {
              type = "boolean",
              default = false,
            },
          },
          { debug_log_saml_response = {
              type = "boolean",
              default = false,
            },
          },
          { debug_log_max_bytes = {
              type = "integer",
              default = 4096,
              between = { 256, 262144 },
            },
          },
          { debug_capture_dir = {
              type = "string",
              default = "",
              len_min = 0,
            },
          },
          { attribute_mappings = {
              type = "array",
              default = {},
              elements = {
                type = "record",
                fields = {
                  { claim = {
                      type = "string",
                      required = true,
                      len_min = 1,
                    },
                  },
                  { saml_attribute = {
                      type = "string",
                      required = true,
                      len_min = 1,
                    },
                  },
                  { upstream_header = {
                      type = "string",
                      required = false,
                      len_min = 1,
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  },
}
