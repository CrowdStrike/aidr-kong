-- Unit tests for AIGuard.guard_stream_response, the STREAMING-stage entry
-- point stream_guard.lua calls into. Stubs kong/ngx/resty.http/
-- kong.llm.plugin.ctx directly (see kong_stubs.lua) rather than going through
-- spec.helpers/pongo, since exercising a real SSE stream end to end would
-- need a live upstream.
local stubs = require("spec.crowdstrike-aidr-shared.kong_stubs")
stubs.install()

local cjson = require("cjson.safe")
local ai_guard = require("kong.plugins.crowdstrike-aidr-shared.ai_guard")

local function sse_event(text)
	return "data: " .. cjson.encode({ choices = { { delta = { content = text } } } }) .. "\n"
end

describe("AIGuard.guard_stream_response", function()
	before_each(function()
		stubs.reset()
		stubs.fake_global_ctx.stream_mode = true
	end)

	it("dispatches a batch once stream_batch_size deltas have arrived", function()
		local conf = {
			ai_guard_api_base_url = "https://api.example.com",
			ai_guard_api_key = "key",
			guard_streaming_response = true,
			stream_batch_size = 2,
		}
		stubs.http_queue = { { status = 200, body = cjson.encode({ result = { blocked = false } }) } }

		ngx.arg = { sse_event("Hel"), false }
		ai_guard.guard_stream_response(conf)
		assert.are.equal(0, #stubs.http_calls)

		ngx.arg = { sse_event("lo"), false }
		ai_guard.guard_stream_response(conf)

		assert.are.equal(1, #stubs.http_calls)
		local sent = cjson.decode(stubs.http_calls[1].opts.body)
		assert.are.equal("Hello", sent.guard_input.messages[1].content)
	end)

	it("flushes any remaining partial batch at end of stream", function()
		local conf = {
			ai_guard_api_base_url = "https://api.example.com",
			ai_guard_api_key = "key",
			guard_streaming_response = true,
			stream_batch_size = 20,
		}
		stubs.http_queue = { { status = 200, body = cjson.encode({ result = { blocked = false } }) } }

		ngx.arg = { sse_event("only one delta"), true }
		ai_guard.guard_stream_response(conf)

		assert.are.equal(1, #stubs.http_calls)
	end)

	it("raises blocked_by_guard on the shared _global ctx when a batch is flagged", function()
		local conf = {
			ai_guard_api_base_url = "https://api.example.com",
			ai_guard_api_key = "key",
			guard_streaming_response = true,
			stream_batch_size = 1,
		}
		stubs.http_queue = { { status = 200, body = cjson.encode({ result = { blocked = true }, summary = "flagged" }) } }

		ngx.arg = { sse_event("bad content"), false }
		ai_guard.guard_stream_response(conf)

		local global_ctx = ngx.ctx.ai_namespaced_ctx and ngx.ctx.ai_namespaced_ctx["_global"]
		assert.is_not_nil(global_ctx)
		assert.is_not_nil(global_ctx.blocked_by_guard)
	end)

	it("stops dispatching further batches once blocked_by_guard is set", function()
		local conf = {
			ai_guard_api_base_url = "https://api.example.com",
			ai_guard_api_key = "key",
			guard_streaming_response = true,
			stream_batch_size = 1,
		}
		stubs.http_queue = { { status = 200, body = cjson.encode({ result = { blocked = true }, summary = "flagged" }) } }

		ngx.arg = { sse_event("bad content"), false }
		ai_guard.guard_stream_response(conf)

		stubs.http_calls = {}
		ngx.arg = { sse_event("more content"), true }
		ai_guard.guard_stream_response(conf)

		assert.are.equal(0, #stubs.http_calls)
	end)

	it("short-circuits with no state when guard_streaming_response is false", function()
		local conf = { guard_streaming_response = false }

		ngx.arg = { sse_event("ignored"), true }
		local ok = ai_guard.guard_stream_response(conf)

		assert.is_true(ok)
		assert.is_nil(kong.ctx.plugin.aidr_stream)
	end)

	it("does nothing on a non-streaming, non-200, or non-service response", function()
		local conf = {
			ai_guard_api_base_url = "https://api.example.com",
			ai_guard_api_key = "key",
			guard_streaming_response = true,
			stream_batch_size = 1,
		}
		stubs.fake_global_ctx.stream_mode = nil -- not an AI Gateway streaming route

		ngx.arg = { sse_event("ignored"), true }
		local ok = ai_guard.guard_stream_response(conf)

		assert.is_true(ok)
		assert.are.equal(0, #stubs.http_calls)
	end)
end)
