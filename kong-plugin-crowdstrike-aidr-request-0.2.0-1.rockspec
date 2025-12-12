local package_version = "0.2.0"
local rockspec_revision = "1"

package = "kong-plugin-crowdstrike-aidr-request"
version = package_version .. "-" .. rockspec_revision
source = {
	url = "git+ssh://git@github.com/crowdstrike/aidr-kong.git",
	tag = "v" .. package_version,
}

description = {
	summary = "Kong Gateway plugin to integrate CrowdStrike AIDR",
	detailed = [[
		kong-plugin-crowdstrike-aidr-request is able to pass proxied LLM requests to CrowdStrike AIDR.
		It will respect the AIDR when determining which actions to take, meaning it may decide to
		completely block any content, or it may redact content before passing it to the consumer.
		It does not need Kong AI Proxy or Kong AI Gateway to be configured, but it can work in
		conjunction with it.
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
		["kong.plugins.crowdstrike-aidr-request.handler"] = "kong/plugins/crowdstrike-aidr-request/handler.lua",
		["kong.plugins.crowdstrike-aidr-request.schema"] = "kong/plugins/crowdstrike-aidr-request/schema.lua",
	},
}
