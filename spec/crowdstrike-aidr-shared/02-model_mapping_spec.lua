-- Unit tests for AIGuard.get_aidr_fields' dynamic model-mapping fallback.
-- These stub the `kong`/`ngx` globals directly rather than going through
-- spec.helpers/pongo, since get_aidr_fields has no dependency on a running
-- Kong instance beyond those two globals.
require("spec.crowdstrike-aidr-shared.kong_stubs").install()

local ai_guard = require("kong.plugins.crowdstrike-aidr-shared.ai_guard")

describe("AIGuard.get_aidr_fields dynamic model mapping", function()
	local base_config

	before_each(function()
		base_config = {
			ai_guard_api_base_url = "https://api.example.com",
			ai_guard_api_key = "key",
			upstream_llm = { provider = "openai", api_uri = "/v1/chat/completions" },
		}
	end)

	it("falls back to the request/response body's model when config.model is unset", function()
		local fields = ai_guard.get_aidr_fields(base_config, "request", { model = "gpt-4o-from-body" })
		assert.are.equal("gpt-4o-from-body", fields.model)
	end)

	it("prefers a static config.model over the body's model", function()
		base_config.model = "static-config-model"
		local fields = ai_guard.get_aidr_fields(base_config, "request", { model = "gpt-4o-from-body" })
		assert.are.equal("static-config-model", fields.model)
	end)

	it("omits model when neither config nor body provide one", function()
		local fields = ai_guard.get_aidr_fields(base_config, "request", nil)
		assert.is_nil(fields.model)
	end)

	it("ignores a non-string body.model", function()
		local fields = ai_guard.get_aidr_fields(base_config, "request", { model = 123 })
		assert.is_nil(fields.model)
	end)
end)
