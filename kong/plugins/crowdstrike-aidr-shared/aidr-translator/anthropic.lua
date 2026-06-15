local Model = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator.model")

-- Convert Anthropic tool definitions to AIDR/OpenAI format.
-- Anthropic: { name, description, input_schema }
-- AIDR:      { type = "function", function = { name, description, parameters } }
local function convert_tools(anthropic_tools)
	local tools = {}
	for _, tool in ipairs(anthropic_tools) do
		if type(tool) == "table" and type(tool.name) == "string" then
			table.insert(tools, {
				type = "function",
				["function"] = {
					name = tool.name,
					description = tool.description,
					parameters = tool.input_schema,
				},
			})
		end
	end
	return tools
end

-- Extract inspectable text from a single content part in an Anthropic message.
-- Adds entries to ret (JSONMessageMap) for text and tool_result blocks.
-- tool_use blocks are skipped (no text to inspect; they carry function name + input).
local function add_content_part(ret, part, role, idx, jdx)
	if part.type == "text" and type(part.text) == "string" then
		ret:add_message(part.text, role, { "messages", idx, "content", jdx, "text" })

	elseif part.type == "tool_result" then
		-- Tool execution output — may contain PII or injected content.
		-- tool_result.content is either a string or an array of content blocks.
		local tool_content = part.content
		if type(tool_content) == "string" then
			ret:add_message(tool_content, role, { "messages", idx, "content", jdx, "content" })
		elseif type(tool_content) == "table" then
			for kdx, block in ipairs(tool_content) do
				if block.type == "text" and type(block.text) == "string" then
					ret:add_message(block.text, role, { "messages", idx, "content", jdx, "content", kdx, "text" })
				end
			end
		end
	end
	-- tool_use, image, document, etc. — no plain text to inspect, skip.
end

-- Build a JSONMessageMap from an Anthropic /v1/messages request body.
-- Handles the full Anthropic content block vocabulary, including tool_result.
local function prepare_messages_request(request)
	if type(request) ~= "table" then
		return nil, "Invalid llm request"
	end

	local ret = Model.NewJSONMessageMap()

	for idx, message in ipairs(request.messages or {}) do
		local role = message.role
		local content = message.content

		if type(content) == "string" then
			ret:add_message(content, role, { "messages", idx, "content" })
		elseif type(content) == "table" then
			for jdx, part in ipairs(content) do
				add_content_part(ret, part, role, idx, jdx)
			end
		end
	end

	return ret
end

local function prepare_messages_response(response)
	if type(response) ~= "table" then
		return nil, "Invalid response object"
	end

	if response.type ~= "message" then
		return nil, "Invalid response object"
	end

	local content = response.content
	if type(content) ~= "table" then
		return nil, "Invalid response object"
	end

	local role = response.role or "assistant"

	local ret = Model.NewJSONMessageMap()
	for idx, part in ipairs(content) do
		-- Only text blocks are prompt content we can guard.
		if type(part) == "table" and part.type == "text" and type(part.text) == "string" then
			ret:add_message(part.text, role, { "content", idx, "text" })
		end
	end

	return ret
end

return {
	["/v1/messages"] = {

		-- Anthropic is similar to OpenAI API format, except they have a special spot for "system" prompts
		["request"] = function(request)
			local ret, err = prepare_messages_request(request)
			if err ~= nil or ret == nil then
				return ret, err
			end

			local system = request.system
			if system ~= nil then
				if type(system) == "string" then
					ret:add_message(system, "system", { "system" })
				elseif type(system) == "table" then
					for idx, content in ipairs(system) do
						if content.type == "text" then
							ret:add_message(content.text, "system", { "system", idx, "text" }, 1)
						end
					end
				end
			end

			-- Convert Anthropic tool definitions to AIDR/OpenAI format
			if type(request.tools) == "table" and #request.tools > 0 then
				ret.tools = convert_tools(request.tools)
			end

			return ret
		end,

		["response"] = prepare_messages_response,
	},
}
