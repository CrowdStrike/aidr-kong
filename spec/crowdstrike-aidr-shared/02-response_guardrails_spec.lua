-- Unit tests for AIGuard.guard_buffered_response, the function
-- crowdstrike-aidr-response's Guardrails-framework handler calls from its
-- registered "guard-buffered-response" function. These stub resty.http (the
-- only real network dependency) directly rather than going through
-- spec.helpers/pongo.
local stubs = require("spec.crowdstrike-aidr-shared.kong_stubs")
stubs.install()

local cjson = require("cjson.safe")
local ai_guard = require("kong.plugins.crowdstrike-aidr-shared.ai_guard")

describe("AIGuard.guard_buffered_response", function()
	local config
	local response_body

	before_each(function()
		stubs.reset()
		config = {
			ai_guard_api_base_url = "https://api.example.com",
			ai_guard_api_key = "key",
			upstream_llm = { provider = "openai", api_uri = "/v1/chat/completions" },
		}
		response_body = cjson.encode({
			id = "chatcmpl-1",
			-- Deliberately omit `object`: this is the AI Proxy Advanced
			-- normalization case the openai.lua translator fix handles.
			choices = {
				{ index = 0, message = { role = "assistant", content = "Hello there" }, finish_reason = "stop" },
			},
		})
	end)

	it("returns block=false, unmasked for an allowed response", function()
		stubs.http_queue = { { status = 200, body = cjson.encode({ result = { blocked = false, transformed = false } }) } }

		local resp, err = ai_guard.guard_buffered_response(config, response_body)

		assert.is_nil(err)
		assert.is_false(resp.block)
		assert.is_nil(resp.masked)
	end)

	it("blocks and surfaces the AIDR summary as the reason", function()
		stubs.http_queue = { { status = 200, body = cjson.encode({ result = { blocked = true }, summary = "unsafe content" }) } }

		local resp = ai_guard.guard_buffered_response(config, response_body)

		assert.is_true(resp.block)
		assert.are.equal("unsafe content", resp.block_message.reason)
	end)

	it("masks the response and rewrites the body when AIDR redacts", function()
		stubs.http_queue = {
			{
				status = 200,
				body = cjson.encode({
					result = {
						blocked = false,
						transformed = true,
						guard_output = { messages = { { role = "assistant", content = "Redacted" } } },
					},
				}),
			},
		}

		local resp = ai_guard.guard_buffered_response(config, response_body)

		assert.is_false(resp.block)
		assert.is_true(resp.masked)
		local decoded = cjson.decode(resp.body)
		assert.are.equal("Redacted", decoded.choices[1].message.content)
	end)

	it("returns an error instead of raising when the body isn't valid JSON", function()
		local resp, err = ai_guard.guard_buffered_response(config, "not json")

		assert.is_nil(resp)
		assert.is_not_nil(err)
	end)

	it("returns an error when CrowdStrike AIDR is unreachable", function()
		stubs.http_queue = { { err = "connection refused" } }

		local resp, err = ai_guard.guard_buffered_response(config, response_body)

		assert.is_nil(resp)
		assert.matches("connection refused", err, 1, true)
	end)
end)
