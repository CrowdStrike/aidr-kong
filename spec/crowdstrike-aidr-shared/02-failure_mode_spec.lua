local cjson = require("cjson")
local helpers = require("spec.helpers")

local PLUGINS = { "crowdstrike-aidr-request", "crowdstrike-aidr-response", "crowdstrike-aidr-mcp" }

local MCP_RESPONSE = cjson.encode({
	jsonrpc = "2.0",
	id = 1,
	result = {
		tools = { { name = "read_doc", description = "Read a doc", inputSchema = { type = "object" } } },
		content = { { type = "text", text = "doc contents" } },
	},
})

local LLM_REQUEST = cjson.encode({
	model = "gpt-4",
	messages = { { role = "user", content = "hello" } },
})

local LLM_RESPONSE = cjson.encode({
	id = "chatcmpl-1",
	object = "chat.completion",
	choices = { { index = 0, message = { role = "assistant", content = "hi there" }, finish_reason = "stop" } },
})

local OPENAI = { provider = "openai", api_uri = "/v1/chat/completions" }

local CASES = {
	{
		name = "mcp-tools-call",
		plugin = "crowdstrike-aidr-mcp",
		upstream = "/fake-mcp",
		upstream_body = MCP_RESPONSE,
		request = cjson.encode({ jsonrpc = "2.0", id = 1, method = "tools/call", params = { name = "read_doc" } }),
	},
	{
		name = "mcp-tools-list",
		plugin = "crowdstrike-aidr-mcp",
		upstream = "/fake-mcp",
		upstream_body = MCP_RESPONSE,
		request = cjson.encode({ jsonrpc = "2.0", id = 1, method = "tools/list" }),
	},
	{
		name = "llm-request",
		plugin = "crowdstrike-aidr-request",
		upstream = "/fake-llm",
		upstream_body = LLM_RESPONSE,
		request = LLM_REQUEST,
		upstream_llm = OPENAI,
	},
	{
		name = "llm-response",
		plugin = "crowdstrike-aidr-response",
		upstream = "/fake-llm",
		upstream_body = LLM_RESPONSE,
		request = LLM_REQUEST,
		upstream_llm = OPENAI,
	},
}

for _, strategy in helpers.each_strategy() do
	describe("failure_mode [" .. strategy .. "]", function()
		local client

		lazy_setup(function()
			local bp = helpers.get_db_utils(strategy, nil, PLUGINS)
			local kong_url = "http://127.0.0.1:" .. helpers.get_proxy_port()

			local function fake(path, status, body)
				local route = bp.routes:insert({ paths = { path } })
				bp.plugins:insert({
					name = "request-termination",
					route = { id = route.id },
					config = { status_code = status, body = body, content_type = "application/json" },
				})
			end
			fake("/fake-aidr", 413, '{"status":"Request Entity Too Large"}')
			fake("/fake-mcp", 200, MCP_RESPONSE)
			fake("/fake-llm", 200, LLM_RESPONSE)

			for _, case in ipairs(CASES) do
				for _, mode in ipairs({ "closed", "open" }) do
					local service = bp.services:insert({ url = kong_url .. case.upstream })
					local route = bp.routes:insert({ service = service, paths = { "/" .. case.name .. "-" .. mode } })
					bp.plugins:insert({
						name = case.plugin,
						route = { id = route.id },
						config = {
							ai_guard_api_key = "test",
							ai_guard_api_base_url = kong_url .. "/fake-aidr",
							-- Leave "closed" unset to check that it is the default.
							failure_mode = mode == "open" and "open" or nil,
							upstream_llm = case.upstream_llm,
						},
					})
				end
			end

			assert(helpers.start_kong({
				database = strategy,
				plugins = "bundled," .. table.concat(PLUGINS, ","),
			}))
		end)

		lazy_teardown(function()
			helpers.stop_kong()
		end)

		before_each(function()
			client = helpers.proxy_client()
		end)

		after_each(function()
			if client then
				client:close()
			end
		end)

		for _, case in ipairs(CASES) do
			it(case.name .. " rejects traffic AIDR cannot inspect by default", function()
				local res = client:post("/" .. case.name .. "-closed", {
					headers = { ["Content-Type"] = "application/json" },
					body = case.request,
				})
				assert.res_status(500, res)
			end)

			it(case.name .. " passes traffic AIDR cannot inspect when failure_mode is open", function()
				local res = client:post("/" .. case.name .. "-open", {
					headers = { ["Content-Type"] = "application/json" },
					body = case.request,
				})
				local body = assert.res_status(200, res)
				assert.same(cjson.decode(case.upstream_body), cjson.decode(body))
			end)
		end
	end)
end
