local package_version = "0.4.0"
local rockspec_revision = "1"

package = "kong-plugin-crowdstrike-aidr-mcp"
version = package_version .. "-" .. rockspec_revision
source = {
	url = "git+ssh://git@github.com/crowdstrike/aidr-kong.git",
	tag = "v" .. package_version,
}

description = {
	summary = "Kong Gateway plugin to integrate CrowdStrike AIDR with MCP servers",
	detailed = [[
		kong-plugin-crowdstrike-aidr-mcp inspects MCP JSON-RPC traffic (tools/list and
		tools/call) using CrowdStrike AIDR. It detects tool poisoning in tool definitions,
		malicious content in tool call arguments, and sensitive data in tool outputs.
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
		["kong.plugins.crowdstrike-aidr-mcp.handler"] = "kong/plugins/crowdstrike-aidr-mcp/handler.lua",
		["kong.plugins.crowdstrike-aidr-mcp.schema"]  = "kong/plugins/crowdstrike-aidr-mcp/schema.lua",
	},
}
