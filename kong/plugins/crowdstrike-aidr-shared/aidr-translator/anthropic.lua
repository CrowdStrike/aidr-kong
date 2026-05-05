local Model = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator.model")
local OpenAiTranslator = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator.openai")

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
			local ret, err = OpenAiTranslator["/v1/chat/completions"].request(request)
			if err ~= nil or ret == nil then
				return ret, err
			end

			local system = request.system
			if system == nil then
				return ret
			end

			if type(system) == "string" then
				ret:add_message(system, "system", { "system" })
			elseif type(system) == "table" then
				for idx, content in ipairs(system) do
					if content.type == "text" then
						ret:add_message(content.text, "system", { "system", idx, "text" }, 1)
					end
				end
			end

			return ret
		end,

		["response"] = prepare_messages_response,
	},
}
