-- Streaming (SSE) guard filter for the crowdstrike-aidr-response plugin.
--
-- Kong's AI Gateway fully supports SSE: on a streaming response the
-- kong.llm.plugin framework runs the STREAMING stage (base.lua:body_filter ->
-- run_stage(STAGES.STREAMING)) instead of the buffered :response path, and
-- ai-proxy-advanced's own normalize-sse-chunk filter (higher priority, so it
-- runs first in body_filter) has already normalized ngx.arg[1] into OpenAI SSE
-- frames by the time we see it.
--
-- The buffered guard (guard-buffered-response) never fires for streams, which
-- is why streaming responses previously went uninspected. This filter closes
-- that gap. Unlike the framework's stock guard-stream-response filter, we run in
-- the request context (not an ngx.timer), so we can resolve the per-request AIDR
-- fields (source_ip, user_id, service name) that live behind kong.client.* /
-- kong.router.*, then hand a fully-prepared, correlated payload to a background
-- timer for the actual CrowdStrike call.
--
-- Semantics: we do NOT block or rewrite the stream. Deltas continue flowing to
-- the client untouched while we aggregate them into batches and, in parallel,
-- ship each batch to CrowdStrike AIDR for logging/flagging.
local ai_guard = require("kong.plugins.crowdstrike-aidr-shared.ai_guard")

local _M = {
	NAME = "crowdstrike-aidr-stream-guard",
	STAGE = "STREAMING",
	DESCRIPTION = "Buffer SSE deltas into correlated batches and flag them with CrowdStrike AIDR (non-blocking)",
	-- STREAMING is a repeated phase; REPEATABLE makes this filter run on every
	-- body_filter invocation for the life of the stream.
	REPEATABLE = true,
}

function _M:run(conf)
	return ai_guard.guard_stream_response(conf)
end

return _M
