local package_version = "0.3.0"
local rockspec_revision = "1"

package = "kong-plugin-crowdstrike-aidr-response"
version = package_version .. "-" .. rockspec_revision
source = {
	url = "git+ssh://git@github.com/crowdstrike/aidr-kong.git",
	tag = "v" .. package_version,
}

description = {
	summary = "Kong Gateway plugin to integrate CrowdStrike AIDR for response inspection",
	detailed = [[
		kong-plugin-crowdstrike-aidr-response inspects LLM responses for PII and sensitive content.
		It works with Kong AI Gateway (ai-proxy/ai-proxy-advanced) to inspect and optionally redact
		responses before they reach the client.

		The plugin uses Kong's response phase to buffer and inspect the complete response,
		then calls CrowdStrike AIDR for PII detection and redaction.

		This plugin is compatible with Kong AI Gateway plugins and does not interfere with
		their routing, load balancing, or failover features.
	]],
	homepage = "https://github.com/crowdstrike/aidr-kong",
	license = "MIT",
}

dependencies = {
	"lua >= 5.1",
	"kong-plugin-crowdstrike-aidr-shared == " .. package_version,
}

build = {
	type = "builtin",
	modules = {
		["kong.plugins.crowdstrike-aidr-response.handler"] = "kong/plugins/crowdstrike-aidr-response/handler.lua",
		["kong.plugins.crowdstrike-aidr-response.schema"] = "kong/plugins/crowdstrike-aidr-response/schema.lua",
	},
}
