local package_version = "0.2.0"
local rockspec_revision = "1"

package = "kong-plugin-crowdstrike-aidr-response"
version = package_version .. "-" .. rockspec_revision
source = {
	url = "git+ssh://git@github.com/crowdstrike/aidr-kong.git",
	tag = "v" .. package_version,
}

description = {
	summary = "Kong Gateway plugin to integrate CrowdStrike AIDR",
	detailed = [[
		kong-plugin-crowdstrike-aidr-response is able to pass proxied LLM requests to CrowdStrike AIDR.
		It will respect the AIDR when determining which actions to take, meaning it may decide to
		completely block any content, or it may redact content before passing it to the consumer.
		It does not need Kong AI Proxy or Kong AI Gateway to be configured, but it can work in
		conjunction with it.

		As a compatability note with other plugins, this "shortcircuits" the request in the access() phase,
		the result being that any other plugin which works in the access() phase after this one will be skipped.
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
