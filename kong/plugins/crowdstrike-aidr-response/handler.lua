local kong_utils = require("kong.tools.gzip")

local ai_guard = require("kong.plugins.crowdstrike-aidr-shared.ai_guard")

-- Plugin class
local CrowdStrikeAIDRResponseHandler = {
	PRIORITY = 760,
	VERSION = "0.3.0",
}

function CrowdStrikeAIDRResponseHandler:access(config)
	kong.service.request.enable_buffering()
end

function CrowdStrikeAIDRResponseHandler:response(config)
	local raw_body = kong.service.response.get_raw_body()
	local status = kong.service.response.get_status()
	local headers = kong.service.response.get_headers()

	if status ~= 200 then
		return kong.response.exit(status, raw_body, headers)
	end

	local encoding = headers["Content-Encoding"]
	if encoding == "gzip" then
		raw_body = kong_utils.inflate_gzip(raw_body)
	end

	local updated_response = ai_guard.run_ai_guard(config, "response", raw_body)
	if updated_response ~= nil then
		raw_body = updated_response
	end

	headers["content-length"] = nil
	headers["content-encoding"] = nil
	headers["content-type"] = "application/json"

	return kong.response.exit(status, raw_body, headers)
end

return CrowdStrikeAIDRResponseHandler
