-- Built on Kong's Guardrails plugin framework (kong.llm.plugin.guardrail_plugin), the
-- same framework Kong's own bundled AI guardrail plugins (e.g. ai-lakera-guard) use.
--
-- The previous handler read kong.service.response.get_raw_body()/kong.response.get_raw_body()
-- directly from a bare :response() phase handler. Neither ever reflects ai-proxy-advanced's
-- provider-format normalization (e.g. Anthropic /v1/messages -> OpenAI chat-completions on a
-- unified, llm_format = "openai" route) - that normalized body lives only in ai-proxy-advanced's
-- private kong.llm.plugin.ctx state. Exiting with the raw upstream body on a cross-format route
-- clobbered the client-facing OpenAI contract.
--
-- The Guardrails framework's guard-buffered-response filter reads via
-- ai_plugin_ctx.get_response_body(), which resolves to that same shared ctx (falling back to
-- the raw upstream body only when no AI proxy plugin ran), and applies masked output via
-- ngx.ctx.buffered_body - the path ai-proxy-advanced's own response pipeline actually consumes.
local Guardrail_Plugin_Builder = require("kong.llm.plugin.guardrail_plugin")
local ai_guard = require("kong.plugins.crowdstrike-aidr-shared.ai_guard")

local PLUGIN_NAME = "crowdstrike-aidr-response"

local plugin = Guardrail_Plugin_Builder.new({
	NAME = PLUGIN_NAME,
	PRIORITY = 760,
	MANIFESTS = {
		can_guard_buffered_response = true,
	},
})

plugin:register_function("guard-buffered-response", function(conf, body)
	return ai_guard.guard_buffered_response(conf, body)
end)

return plugin:build()
