local ai_guard = require("kong.plugins.crowdstrike-aidr-shared.ai_guard")
local kong_utils = require("kong.tools.gzip")

-- Plugin class
local CrowdStrikeAIDRRequestHandler = {
	-- Need to run BEFORE ai-proxy
	PRIORITY = 780,
	VERSION = "0.3.0",
}

-- Cap for reading request bodies that nginx has spooled to a temp file.
-- CrowdStrike AIDR's maximum request body size is 1 MiB, so there is little use
-- in reading bodies that are larger than that.
-- <https://aidr-docs.crowdstrike.com/docs/aidr/apis#request-parameters>
local MAX_BUFFERED_BODY_SIZE = 1024 * 1024

local function get_raw_body()
	local raw_body, err = kong.request.get_raw_body(MAX_BUFFERED_BODY_SIZE)
	if raw_body == nil then
		return nil, err
	end

	local encoding = kong.request.get_header("Content-Encoding")
	if encoding == "gzip" then
		raw_body = kong_utils.inflate_gzip(raw_body)
	end

	return raw_body
end

function CrowdStrikeAIDRRequestHandler:access(config)
	local method = kong.request.get_method()
	if method ~= "POST" and method ~= "PUT" and method ~= "PATCH" then
		return
	end

	local raw_body, err = get_raw_body()
	if raw_body == nil then
		kong.log.err("Failed to read request body, skipping AIDR: ", err)
		return
	end
	if raw_body == "" then
		kong.log.debug("No body found, skipping AIDR")
		return
	end

	local new_payload = ai_guard.run_ai_guard(config, "request", raw_body)
	if new_payload ~= nil then
		kong.service.request.set_raw_body(new_payload)
	end
end

return CrowdStrikeAIDRRequestHandler
