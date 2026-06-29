local cjson = require("cjson.safe")
local http = require("resty.http")

local CrowdStrikeAIDRMcpPlugin = {
	-- Run before the ai-mcp-proxy plugin in the access phase so we can inspect
	-- and block tool_input before the tool executes. Priority tuning against
	-- Kong's ai-mcp-proxy priority may be needed for your deployment.
	PRIORITY = 790,
	VERSION = "0.4.0",
}

-- Key used to pass state from the access phase to the response phase.
local CTX_KEY = "crowdstrike_aidr_mcp"

-- Maximum request body size sent to AIDR (matches the 1 MiB AIDR API limit).
local MAX_BODY_SIZE = 1024 * 1024

-- ---------------------------------------------------------------------------
-- MCP format helpers
-- ---------------------------------------------------------------------------

-- Convert a single MCP tool definition to AIDR/OpenAI format.
-- MCP:  { name, description, inputSchema }
-- AIDR: { type = "function", function = { name, description, parameters } }
local function mcp_tool_to_aidr(tool)
	if type(tool) ~= "table" or type(tool.name) ~= "string" then
		return nil
	end
	return {
		type = "function",
		["function"] = {
			name        = tool.name,
			description = tool.description,
			parameters  = tool.inputSchema,
		},
	}
end

-- Build a JSON-RPC 2.0 error response body.
-- id may be a number, string, or nil/null (cjson encodes nil as null).
local function jsonrpc_error(id, message)
	local obj = {
		jsonrpc = "2.0",
		error = {
			code    = -32603,
			message = message,
		},
		id = id,
	}
	local encoded, err = cjson.encode(obj)
	if err then
		-- Fall back to a static error if encoding fails.
		return '{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal error"},"id":null}'
	end
	return encoded
end

-- ---------------------------------------------------------------------------
-- AIDR HTTP call
-- ---------------------------------------------------------------------------

-- Resolve user_id (machine identifier) and user_name (display name) from Kong
-- auth context, falling back to config.
local function resolve_user(config)
	local consumer = kong.client.get_consumer()
	if consumer then
		local user_id   = consumer.custom_id or consumer.id
		local user_name = consumer.username
		if user_id or user_name then
			return user_id, user_name
		end
	end

	local credential = kong.client.get_credential()
	if credential then
		return credential.id, nil
	end

	local cfg_id   = config.user_id   ~= ngx.null and config.user_id   or nil
	local cfg_name = config.user_name ~= ngx.null and config.user_name or nil
	return cfg_id, cfg_name
end

-- Call AIDR with the given event_type and guard_input.
-- Returns the parsed AIDR response table, or nil + error string on failure.
local function call_aidr(config, event_type, guard_input)
	local url = config.ai_guard_api_base_url .. "/v1/guard_chat_completions"

	local body = {
		source_ip  = kong.client.get_forwarded_ip(),
		event_type = event_type,
		guard_input = guard_input,
	}

	if config.app_id and config.app_id ~= ngx.null then
		body.app_id = config.app_id
	end
	local user_id, user_name = resolve_user(config)
	if user_id then
		body.user_id = user_id
	end
	if config.source_location and config.source_location ~= ngx.null then
		body.source_location = config.source_location
	end
	if config.tenant_id and config.tenant_id ~= ngx.null then
		body.tenant_id = config.tenant_id
	end
	if config.collector_instance_id and config.collector_instance_id ~= ngx.null then
		body.collector_instance_id = config.collector_instance_id
	end

	local service = kong.router.get_service()
	body.extra_info = {}
	if service and service.name then
		body.extra_info.app_name = service.name
	end
	if user_name then
		body.extra_info.user_name = user_name
	end
	if config.extra_info and config.extra_info ~= ngx.null then
		for k, v in pairs(config.extra_info) do
			body.extra_info[k] = v
		end
	end

	local raw_body, err = cjson.encode(body)
	if err then
		return nil, "encode: " .. err
	end

	local httpc = http.new()
	local res, req_err = httpc:request_uri(url, {
		method  = "POST",
		body    = raw_body,
		headers = {
			["Authorization"] = "Bearer " .. config.ai_guard_api_key,
			["Content-Type"]  = "application/json",
		},
	})

	if req_err then
		return nil, "http: " .. req_err
	end

	if res.status ~= 200 then
		return nil, "status: " .. res.status
	end

	local response, decode_err = cjson.decode(res.body)
	if decode_err then
		return nil, "decode: " .. decode_err
	end

	return response, nil
end

-- ---------------------------------------------------------------------------
-- Access phase — inspect tool_input
-- ---------------------------------------------------------------------------

function CrowdStrikeAIDRMcpPlugin:access(config)
	if kong.request.get_method() ~= "POST" then
		return
	end

	local raw_body, err = kong.request.get_raw_body(MAX_BODY_SIZE)
	if not raw_body or raw_body == "" then
		if err then
			kong.log.debug("Could not read MCP request body: ", err)
		end
		return
	end

	local body, parse_err = cjson.decode(raw_body)
	if parse_err or type(body) ~= "table" then
		return
	end

	-- Only handle JSON-RPC 2.0 requests.
	if body.jsonrpc ~= "2.0" or type(body.method) ~= "string" then
		return
	end

	local method = body.method
	local id     = body.id

	-- Store for the response phase (only for methods we inspect there).
	if method == "tools/call" or method == "tools/list" then
		kong.ctx.shared[CTX_KEY] = { method = method, id = id }
	end

	-- Inspect tool inputs before execution.
	if method ~= "tools/call" then
		return
	end

	local params = body.params
	if type(params) ~= "table" or type(params.name) ~= "string" then
		return
	end

	-- Serialise tool name + arguments into a single content string so AIDR's
	-- text-based detectors (malicious prompt, PII, etc.) can analyse them.
	local tool_name = params.name
	local args_str
	if type(params.arguments) == "table" then
		args_str = cjson.encode(params.arguments)
	elseif type(params.arguments) == "string" then
		args_str = params.arguments
	end

	local content = tool_name
	if args_str then
		content = tool_name .. ": " .. args_str
	end

	local aidr_res, call_err = call_aidr(config, "tool_input", {
		messages = { { role = "user", content = content } },
	})

	if call_err then
		kong.log.err("AIDR tool_input check failed: ", call_err)
		kong.response.exit(500, jsonrpc_error(id, "AIDR inspection failed"), {
			["Content-Type"] = "application/json",
		})
	end

	if type(aidr_res.result) ~= "table" then
		kong.log.err("AIDR tool_input: missing or invalid result field")
		kong.response.exit(500, jsonrpc_error(id, "AIDR inspection failed"), {
			["Content-Type"] = "application/json",
		})
	end

	if aidr_res.result.blocked == true then
		local msg = aidr_res.summary or "Tool call blocked by CrowdStrike AIDR policy"
		kong.response.exit(400, jsonrpc_error(id, msg), {
			["Content-Type"] = "application/json",
		})
	end
end

-- ---------------------------------------------------------------------------
-- Response phase — inspect tool_listing and tool_output
-- ---------------------------------------------------------------------------

function CrowdStrikeAIDRMcpPlugin:response(config)
	local ctx = kong.ctx.shared[CTX_KEY]
	if not ctx then
		return
	end

	local method = ctx.method
	local id     = ctx.id

	if method ~= "tools/list" and method ~= "tools/call" then
		return
	end

	-- Skip non-200 upstream responses.
	if kong.service.response.get_status() ~= 200 then
		return
	end

	local raw_body = kong.service.response.get_raw_body()
	if not raw_body or raw_body == "" then
		return
	end

	local body, parse_err = cjson.decode(raw_body)
	if parse_err or type(body) ~= "table" then
		return
	end

	-- JSON-RPC errors from the upstream MCP server — nothing to inspect.
	if body.error ~= nil then
		return
	end

	local result = body.result
	if type(result) ~= "table" then
		return
	end

	-- ----- tools/list → tool_listing -----
	if method == "tools/list" then
		local tools = result.tools
		if type(tools) ~= "table" or #tools == 0 then
			return
		end

		local aidr_tools = {}
		for _, tool in ipairs(tools) do
			local converted = mcp_tool_to_aidr(tool)
			if converted then
				table.insert(aidr_tools, converted)
			end
		end

		if #aidr_tools == 0 then
			return
		end

		local aidr_res, call_err = call_aidr(config, "tool_listing", {
			tools = aidr_tools,
		})

		if call_err then
			kong.log.err("AIDR tool_listing check failed: ", call_err)
			kong.response.exit(500, jsonrpc_error(id, "AIDR inspection failed"), {
				["Content-Type"] = "application/json",
			})
		end

		if type(aidr_res.result) ~= "table" then
			kong.log.err("AIDR tool_listing: missing or invalid result field")
			kong.response.exit(500, jsonrpc_error(id, "AIDR inspection failed"), {
				["Content-Type"] = "application/json",
			})
		end

		if aidr_res.result.blocked == true then
			local msg = aidr_res.summary or "Tool listing blocked by CrowdStrike AIDR policy"
			kong.response.exit(400, jsonrpc_error(id, msg), {
				["Content-Type"] = "application/json",
			})
		end

	-- ----- tools/call → tool_output -----
	elseif method == "tools/call" then
		local content = result.content
		if type(content) ~= "table" or #content == 0 then
			return
		end

		-- Extract text blocks — these are the inspectable tool output.
		local messages = {}
		for _, block in ipairs(content) do
			if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
				table.insert(messages, { role = "tool", content = block.text })
			end
		end

		if #messages == 0 then
			return
		end

		local aidr_res, call_err = call_aidr(config, "tool_output", {
			messages = messages,
		})

		if call_err then
			kong.log.err("AIDR tool_output check failed: ", call_err)
			kong.response.exit(500, jsonrpc_error(id, "AIDR inspection failed"), {
				["Content-Type"] = "application/json",
			})
		end

		if type(aidr_res.result) ~= "table" then
			kong.log.err("AIDR tool_output: missing or invalid result field")
			kong.response.exit(500, jsonrpc_error(id, "AIDR inspection failed"), {
				["Content-Type"] = "application/json",
			})
		end

		if aidr_res.result.blocked == true then
			local msg = aidr_res.summary or "Tool output blocked by CrowdStrike AIDR policy"
			kong.response.exit(400, jsonrpc_error(id, msg), {
				["Content-Type"] = "application/json",
			})
		end
	end
end

return CrowdStrikeAIDRMcpPlugin
