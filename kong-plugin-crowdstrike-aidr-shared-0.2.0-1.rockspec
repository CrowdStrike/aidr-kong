local package_version = "0.2.0"
local rockspec_revision = "1"

package = "kong-plugin-crowdstrike-aidr-shared"
version = package_version .. "-" .. rockspec_revision
source = {
	url = "git+ssh://git@github.com/crowdstrike/aidr-kong.git",
	tag = "v" .. package_version,
}

description = {
	summary = "Kong Gateway plugin to integrate CrowdStrike AIDR",
	detailed = [[
		Implements the shared library for kong-plugin-crowdstrike-aidr-request and kong-plugin-crowdstrike-aidr-response,
		which will use CrowdStrike AIDR as a guardrails for LLM requests / responses.
	]],
	homepage = "https://github.com/crowdstrike/aidr-kong",
	license = "MIT",
}

dependencies = {
	"lua >= 5.1",
}

build = {
	type = "builtin",
	modules = {
		["kong.plugins.crowdstrike-aidr-shared.ai_guard"] = "kong/plugins/crowdstrike-aidr-shared/ai_guard.lua",
		["kong.plugins.crowdstrike-aidr-shared.aidr-translator.init"] = "kong/plugins/crowdstrike-aidr-shared/aidr-translator/init.lua",
		["kong.plugins.crowdstrike-aidr-shared.aidr-translator.model"] = "kong/plugins/crowdstrike-aidr-shared/aidr-translator/model.lua",
		-- List of llm modules -- be sure to keep up to date
		["kong.plugins.crowdstrike-aidr-shared.aidr-translator.anthropic"] = "kong/plugins/crowdstrike-aidr-shared/aidr-translator/anthropic.lua",
		["kong.plugins.crowdstrike-aidr-shared.aidr-translator.azureai"] = "kong/plugins/crowdstrike-aidr-shared/aidr-translator/azureai.lua",
		["kong.plugins.crowdstrike-aidr-shared.aidr-translator.bedrock"] = "kong/plugins/crowdstrike-aidr-shared/aidr-translator/bedrock.lua",
		["kong.plugins.crowdstrike-aidr-shared.aidr-translator.cohere"] = "kong/plugins/crowdstrike-aidr-shared/aidr-translator/cohere.lua",
		["kong.plugins.crowdstrike-aidr-shared.aidr-translator.gemini"] = "kong/plugins/crowdstrike-aidr-shared/aidr-translator/gemini.lua",
		["kong.plugins.crowdstrike-aidr-shared.aidr-translator.kong"] = "kong/plugins/crowdstrike-aidr-shared/aidr-translator/kong.lua",
		["kong.plugins.crowdstrike-aidr-shared.aidr-translator.openai"] = "kong/plugins/crowdstrike-aidr-shared/aidr-translator/openai.lua",
	},
}
