local OpenAiTranslator    = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator.openai")
local AnthropicTranslator = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator.anthropic")
local BedrockTranslator   = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator.bedrock")

-- Kong AI Proxy returns the raw upstream response, so the format depends on
-- which backend the gateway is proxying to.  Sniff distinguishing fields and
-- delegate to the appropriate existing handler rather than assuming OpenAI.
local function detect_and_parse_response(response)
	if type(response) ~= "table" then
		return nil, "Invalid response object"
	end

	-- OpenAI / Azure OpenAI chat completions
	if response.object == "chat.completion" then
		return OpenAiTranslator["/v1/chat/completions"].response(response)
	end

	-- OpenAI legacy completions
	if response.object == "text_completion" then
		return OpenAiTranslator["/v1/completions"].response(response)
	end

	-- Anthropic Messages API
	if response.type == "message" then
		return AnthropicTranslator["/v1/messages"].response(response)
	end

	-- AWS Bedrock Converse API: output is an object {message: {role, content[]}}
	if type(response.output) == "table" and type(response.output.message) == "table" then
		return BedrockTranslator["converse"].response(response)
	end

	return nil, "Unrecognized response format from Kong AI Proxy"
end

local KongAIProxyTranslator = {
	["/llm/v1/chat"] = {
		["request"]  = OpenAiTranslator["/v1/chat/completions"].request,
		["response"] = detect_and_parse_response,
	},
	["/llm/v1/completions"] = {
		["request"]  = OpenAiTranslator["/v1/completions"].request,
		["response"] = OpenAiTranslator["/v1/completions"].response,
	},
}

return KongAIProxyTranslator
