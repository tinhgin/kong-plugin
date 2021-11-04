local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")
local plugin = {
  PRIORITY = 1000, -- set the plugin priority, which determines plugin execution order
  VERSION = "1.0.0",
}


local function split(s, delimiter)
    local table = table
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

local function has_value (tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end



function plugin:init_worker()
  local kong = kong
  kong.worker_events.register(function()
    local cache = kong.cache
    local request_uri_map_keys = cache:get("request_uri_map_keys", nil)
    if request_uri_map_keys ~= nil then
      for i = 1,#request_uri_map_keys do
        local invalidate_key = request_uri_map_keys[i]
        cache:invalidate_local(invalidate_key)
      end
    end
  end, "crud", "plugins")
end



function plugin:access(plugin_conf)
  local kong = kong
  local cache = kong.cache
  local request_uri = kong.request.get_path() -- /v1/customer/login

--  get micro_service_request_uri
  local request_uri_map = cache:get(request_uri, nil)
  local micro_service_request_uri = ""
  local micro_service = ""
  local real_app_version = ""

  if not request_uri_map then
    kong.log.debug("request_uri_map not found in cache")
    local version_map = plugin_conf.version_map -- a dict
    local request_uri_split = split(request_uri, "/") -- a list
    local len_request_uri_split = #request_uri_split
    if len_request_uri_split < 3 then
      return kong.response.exit(404, "{\"" .. plugin_name .. " plugin\":\"no microservice specified in URI\"}", {["Content-Type"] = "application/json; charset=utf-8"})
    end
    local app_version = request_uri_split[2]
    micro_service = request_uri_split[3]
    if (#micro_service == 0) then
      return kong.response.exit(404, "{\"" .. plugin_name .. " plugin\":\"no microservice specified in URI\"}", {["Content-Type"] = "application/json; charset=utf-8"})
    end
    local micro_service_uri = ""
--    if #request_uri_split[len_request_uri_split] == 0 then
--      len_request_uri_split = tonumber(len_request_uri_split) - 1
--    end
    for split_index = 4,len_request_uri_split do
      micro_service_uri = micro_service_uri .. "/" .. request_uri_split[split_index]
    end



    local version_map_value = version_map[app_version]
    if version_map_value == nil then
      return kong.response.exit(404, "{\"" .. plugin_name .. " plugin\":\"app version " .. app_version .. " not found\"}", {["Content-Type"] = "application/json; charset=utf-8"})
    end
    real_app_version = version_map_value["app_version"]
    local microservice_record = version_map_value["microservices"][micro_service]
    if microservice_record == nil then
      return kong.response.exit(404, "{\"" .. plugin_name .. " plugin\":\"microservice " .. micro_service .. " not found\"}", {["Content-Type"] = "application/json; charset=utf-8"})
    end
    local api_allowed = has_value(microservice_record["microservice_apis"], micro_service_uri)
    if api_allowed == false then
      return kong.response.exit(403, "{\"" .. plugin_name .. " plugin\":\"this api is private or not found\"}", {["Content-Type"] = "application/json; charset=utf-8"})
    end
    local micro_service_version = microservice_record["microservice_version"]
    if micro_service_version == nil then
      return kong.response.exit(404, "{\"" .. plugin_name .. " plugin\":\"microservice " .. micro_service .. " not found\"}", {["Content-Type"] = "application/json; charset=utf-8"})
    end
    micro_service_request_uri = "/" .. micro_service .. "/" .. micro_service_version .. micro_service_uri
    request_uri_map = {}
    request_uri_map["request_uri"] = request_uri
    request_uri_map["micro_service_request_uri"] = micro_service_request_uri
    request_uri_map["micro_service"] = micro_service
    request_uri_map["real_app_version"] = real_app_version
    cache:safe_set(request_uri, request_uri_map)
    local request_uri_map_keys = cache:get("request_uri_map_keys", nil)
    if request_uri_map_keys == nil then
      request_uri_map_keys = {}
    end
    table.insert(request_uri_map_keys, request_uri)
    cache:safe_set("request_uri_map_keys", request_uri_map_keys)
  else
    kong.log.debug("found request_uri_map in cache")
    micro_service_request_uri = request_uri_map["micro_service_request_uri"]
    micro_service = request_uri_map["micro_service"]
    real_app_version = request_uri_map["real_app_version"]
  end


--  set path
  kong.service.request.set_path(micro_service_request_uri)

--  set target
  local micro_service_info = plugin_conf.microservice_upstream[micro_service]
  local micro_service_ip = micro_service_info["ip"]
  local service = kong.router.get_service()
  if (micro_service_ip ~= service["host"]) then
    kong.service.set_target(micro_service_ip, 80)
  end


--  set host header

  if micro_service_info == nil then
    return kong.response.exit(404, "{\"" .. plugin_name .. " plugin\":\"domain for " .. micro_service .. " not found\"}", {["Content-Type"] = "application/json; charset=utf-8"})
  end
  local micro_service_domain = micro_service_info["domain"]
  kong.service.request.set_header("Host", micro_service_domain)
  kong.service.request.set_header("App-Version", real_app_version)

  
end


return plugin
