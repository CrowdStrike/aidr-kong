local Model = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator.model")

local role_transform = {
	["developer"] = Model.AidrRoles.PromptRoleSystem,
	["system"] = Model.AidrRoles.PromptRoleSystem,
	["user"] = Model.AidrRoles.PromptRoleUser,
	["assistant"] = Model.AidrRoles.PromptRoleLlm,
}

local function prepare_chat_completions_request(request)
	if type(request) ~= "table" then
		return nil, "Invalid llm request"
	end

	local ret = Model.NewJSONMessageMap()

	for idx, message in ipairs(request.messages) do
		local role = message.role
		local content = message.content
		role = role_transform[role] or role

		-- Content is either a string OR an array of objects
		if type(content) == "string" then
			ret:add_message(content, role, { "messages", idx, "content" })
		elseif type(content) == "table" then
			for jdx, part in ipairs(content) do
				if part.type == "text" then
					ret:add_message(part.text, role, { "messages", idx, "content", jdx, "text" })
				end
			end
		elseif content == nil and type(message.tool_calls) == "table" then
			-- Assistant message with tool calls but no text content.
			-- Add as a context-only entry (nil lookup) so AIDR sees the conversation
			-- boundary; the tool_calls array in the original body is left untouched.
			ret:add_message(nil, "assistant", nil)
		end
	end

	-- Pass tools through as-is; they are already in AIDR/OpenAI format
	if type(request.tools) == "table" and #request.tools > 0 then
		ret.tools = request.tools
	end

	return ret
end

local function prepare_chat_completions_response(response)
	if type(response) ~= "table" then
		return nil, "Invalid response object"
	end

	if response.object ~= "chat.completion" then
		return nil, "Invalid response object"
	end

	local ret = Model.NewJSONMessageMap()

	for idx, choice in ipairs(response.choices) do
		local role = choice.message.role
		local content = choice.message.content
		role = role_transform[role] or role

		if content then
			ret:add_message(content, role, { "choices", idx, "message", "content" })
		end
	end

	return ret
end

local function prepare_completions_request(request)
	if type(request) ~= "table" then
		return nil, "Invalid llm request"
	end

	local ret = Model.NewJSONMessageMap()

	local prompt = request.prompt
	if type(prompt) == "string" then
		ret:add_message(prompt, "user", { "prompt" })
	elseif type(prompt) == "table" then
		for idx, message in ipairs(prompt) do
			ret:add_message(message, "user", { "prompt", idx })
		end
	end

	return ret
end

local function prepare_completions_response(response)
	if type(response) ~= "table" then
		return nil, "Invalid response object"
	end

	if response.object ~= "text_completion" then
		return nil, "Invalid response object"
	end

	local ret = Model.NewJSONMessageMap()

	for idx, choice in ipairs(response.choices) do
		local content = choice.text

		if content then
			ret:add_message(content, "assistant", { "choices", idx, "text" })
		end
	end

	return ret
end

-- Responses API tool definitions are flat ({ type, name, description, parameters }),
-- while AIDR expects the Chat Completions shape ({ type, function = { ... } }).
-- Built-in tools (web_search, file_search, mcp, custom, ...) carry no function schema and are dropped.
local function convert_responses_tools(responses_tools)
	local tools = {}
	for _, tool in ipairs(responses_tools) do
		if type(tool) == "table" and tool.type == "function" and type(tool.name) == "string" then
			table.insert(tools, {
				type = "function",
				["function"] = {
					name = tool.name,
					description = tool.description,
					parameters = tool.parameters,
				},
			})
		end
	end
	return tools
end

-- Add every input_text / output_text part of a Responses content array.
-- Other parts (input_image, input_file, refusal, ...) are skipped.
local function add_responses_text_parts(ret, parts, role, path)
	for jdx, part in ipairs(parts) do
		if
			type(part) == "table"
			and (part.type == "input_text" or part.type == "output_text")
			and type(part.text) == "string"
		then
			local part_path = { unpack(path) }
			table.insert(part_path, jdx)
			table.insert(part_path, "text")
			ret:add_message(part.text, role, part_path)
		end
	end
end

-- Tool output is either a string or an array of content parts.
local function add_responses_tool_output(ret, output, path)
	if type(output) == "string" then
		ret:add_message(output, "tool", path)
	elseif type(output) == "table" then
		add_responses_text_parts(ret, output, "tool", path)
	end
end

-- Map a single Responses `input` item onto the same message shapes the
-- Chat Completions translator produces.
local function add_responses_input_item(ret, item, idx)
	local item_type = item.type

	if item_type == nil or item_type == "message" then
		local role = role_transform[item.role] or item.role
		local content = item.content
		if type(content) == "string" then
			ret:add_message(content, role, { "input", idx, "content" })
		elseif type(content) == "table" then
			add_responses_text_parts(ret, content, role, { "input", idx, "content" })
		end
	elseif item_type == "function_call" or item_type == "custom_tool_call" then
		-- Equivalent of an assistant message with tool_calls and no content:
		-- context-only entry, the call itself is left untouched.
		ret:add_message(nil, "assistant", nil)
	elseif item_type == "function_call_output" or item_type == "custom_tool_call_output" then
		add_responses_tool_output(ret, item.output, { "input", idx, "output" })
	elseif item_type == "mcp_call" then
		-- An mcp_call item holds both the call and its result.
		ret:add_message(nil, "assistant", nil)
		if type(item.output) == "string" then
			ret:add_message(item.output, "tool", { "input", idx, "output" })
		end
	end
	-- reasoning, item_reference, and other built-in tool items are skipped.
end

local function prepare_responses_request(request)
	if type(request) ~= "table" then
		return nil, "Invalid llm request"
	end

	local ret = Model.NewJSONMessageMap()

	if type(request.instructions) == "string" then
		ret:add_message(request.instructions, Model.AidrRoles.PromptRoleSystem, { "instructions" })
	end

	local input = request.input
	if type(input) == "string" then
		ret:add_message(input, Model.AidrRoles.PromptRoleUser, { "input" })
	elseif type(input) == "table" then
		for idx, item in ipairs(input) do
			if type(item) == "table" then
				add_responses_input_item(ret, item, idx)
			end
		end
	end

	if type(request.tools) == "table" then
		local tools = convert_responses_tools(request.tools)
		if #tools > 0 then
			ret.tools = tools
		end
	end

	return ret
end

-- Only output_text parts of `message` output items are inspected, the same
-- way the Chat Completions translator only inspects choices[].message.content.
local function prepare_responses_response(response)
	if type(response) ~= "table" then
		return nil, "Invalid response object"
	end

	if response.object ~= "response" then
		return nil, "Invalid response object"
	end

	local ret = Model.NewJSONMessageMap()

	if type(response.output) ~= "table" then
		return ret
	end

	for idx, item in ipairs(response.output) do
		if type(item) == "table" and item.type == "message" and type(item.content) == "table" then
			local role = role_transform[item.role] or item.role or Model.AidrRoles.PromptRoleLlm
			for jdx, part in ipairs(item.content) do
				if type(part) == "table" and part.type == "output_text" and type(part.text) == "string" then
					ret:add_message(part.text, role, { "output", idx, "content", jdx, "text" })
				end
			end
		end
	end

	return ret
end

local OpenAiTranslator = {
	["/v1/chat/completions"] = {
		["request"] = prepare_chat_completions_request,
		["response"] = prepare_chat_completions_response,
	},
	["/v1/completions"] = {
		["request"] = prepare_completions_request,
		["response"] = prepare_completions_response,
	},
	["/v1/responses"] = {
		["request"] = prepare_responses_request,
		["response"] = prepare_responses_response,
	},
}

return OpenAiTranslator
