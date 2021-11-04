local typedefs = require "kong.db.schema.typedefs"

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local schema = {
  name = plugin_name,
  fields = {
    -- the 'fields' array is the top-level entry with fields defined by Kong
    { consumer = typedefs.no_consumer },  -- this plugin cannot be configured on a consumer (typical for auth plugins)
    { protocols = typedefs.protocols_http },
    { config = {
        -- The 'config' record is the custom part of the plugin schema
        type = "record",
        fields = {
          { microservice_upstream = {
              type = "map",
              keys = {
                type = "string",
                required = true,
              },
              values = {
                type = "record",
                required = true,
                fields = {
                  { domain = typedefs.host({ required = true }), },
                  { ip = typedefs.ip({required = true, }), },
                },
              },
              required = true, }},
          { version_map = { -- self defined field
              type = "map",
              keys = {
                type = "string",
                required = true,
              },
              values = {
                type = "record",
                required = true,
                fields = {
                  { app_version = {type = "string", required = true,} },
                  { microservices = {
                    type = "map",
                    required = true,
                    keys = {
                      type = "string",
                      required = true,
                    },
                    values = {
                      type = "record",
                      required = true,
                      fields = {
                        { microservice_version = { type = "string", required = true }, },
                        { microservice_apis = { type = "array", required = true, elements = { type = "string",  }, }, },
                      },
                    },
                  } },
                },
              },
              required = true, }}, -- adding a constraint for the value
        },
--        entity_checks = {
--          -- add some validation rules across fields
--          -- the following is silly because it is always true, since they are both required
--          { at_least_one_of = { "token_header", "response_header" }, },
--          -- We specify that both header-names cannot be the same
--          { distinct = { "token_header", "response_header"} },
--        },
      },
    },
  },
}

return schema
