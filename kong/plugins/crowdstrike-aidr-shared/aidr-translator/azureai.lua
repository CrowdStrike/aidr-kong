local OpenAiTranslator = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator.openai")

local AzureAITranslator = {
	["/chat/completions"] = {
		["request"] = OpenAiTranslator["/v1/chat/completions"].request,
		["response"] = OpenAiTranslator["/v1/chat/completions"].response,
	},
}

return AzureAITranslator
