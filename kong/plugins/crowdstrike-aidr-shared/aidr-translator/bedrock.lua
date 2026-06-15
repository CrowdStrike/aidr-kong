local Model = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator.model")

-- Convert Bedrock toolSpec definitions to AIDR/OpenAI format.
-- Bedrock: { toolSpec = { name, description, inputSchema = { json = {...} } } }
-- AIDR:    { type = "function", function = { name, description, parameters } }
local function convert_tools(bedrock_tools)
	local tools = {}
	for _, tool in ipairs(bedrock_tools) do
		local spec = type(tool) == "table" and tool.toolSpec
		if spec and type(spec.name) == "string" then
			local parameters = spec.inputSchema and spec.inputSchema.json
			table.insert(tools, {
				type = "function",
				["function"] = {
					name = spec.name,
					description = spec.description,
					parameters = parameters,
				},
			})
		end
	end
	return tools
end

local function prepare_converse_request(request)
	if type(request) ~= "table" then
		return nil, "Invalid llm request"
	end

	local ret = Model.NewJSONMessageMap()

	for idx, system_content in ipairs(request.system) do
		local text = system_content.text
		if text ~= nil then
			ret:add_message(text, "system", { "system", idx, "text" })
		end
	end

	for idx, message in ipairs(request.messages) do
		local role = message.role
		for jdx, content in ipairs(message.content) do
			local text = content.text
			if text ~= nil then
				ret:add_message(text, role, { "messages", idx, "content", jdx, "text" })
			end
		end
	end

	-- Convert Bedrock tool definitions to AIDR/OpenAI format
	local tool_config = request.toolConfig
	if type(tool_config) == "table" and type(tool_config.tools) == "table" and #tool_config.tools > 0 then
		ret.tools = convert_tools(tool_config.tools)
	end

	return ret
end

local function prepare_converse_response(response)
	if type(response) ~= "table" then
		return nil, "Invalid response object"
	end

	-- The Bedrock Converse API returns output as an object: {message: {role, content[]}}
	if type(response.output) ~= "table" or type(response.output.message) ~= "table" then
		return nil, "Invalid response object"
	end

	local ret = Model.NewJSONMessageMap()

	local message = response.output.message
	local role = message.role or "assistant"
	for jdx, content in ipairs(message.content) do
		local text = content.text
		if text ~= nil then
			ret:add_message(text, role, { "output", "message", "content", jdx, "text" })
		end
	end

	return ret
end

return {
	["converse"] = {
		["request"] = prepare_converse_request,
		["response"] = prepare_converse_response,
	},
	-- Might want to reorganize this, or maybe apply this
	-- per transformer -- for now it's fine here -- we have a hard coded
	-- exception around this name in the schema validators
	capabilities = {
		-- Butting into HMAC signing issues, so we can only really block in this case
		redaction = false,
	},
}
