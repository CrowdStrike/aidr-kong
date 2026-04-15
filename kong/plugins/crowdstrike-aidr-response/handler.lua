local ai_guard = require("kong.plugins.crowdstrike-aidr-shared.ai_guard")
local cjson = require("cjson.safe")
local kong_utils = require("kong.tools.gzip")  -- For decompressing gzip responses

-- Plugin class
local CrowdStrikeAIDRResponseHandler = {
	-- Set priority low so that this runs after ai-proxy / ai-proxy-advanced (and our request handler)
	PRIORITY = 760,
	VERSION = "0.3.0",
}

-- Enable response buffering in access phase (runs before ai-proxy-advanced proxies)
function CrowdStrikeAIDRResponseHandler:access(config)
	kong.log.notice("[AIDR-RESPONSE] access() phase called")

	-- Only need to buffer if we're using Kong AI Gateway
	if config.upstream_llm.provider == "kong" then
		kong.log.notice("[AIDR-RESPONSE] Enabling response buffering for AIDR inspection")

		-- Enable response buffering so we can inspect the full response body
		-- in the response phase
		if kong.service.request and kong.service.request.enable_buffering then
			kong.service.request.enable_buffering()
			-- Use kong.ctx.shared to persist across phases
			kong.ctx.shared.aidr_response_buffering = true
			kong.log.notice("[AIDR-RESPONSE] Buffering enabled via kong.service.request.enable_buffering()")
		else
			-- Fallback for older Kong versions
			kong.log.notice("[AIDR-RESPONSE] Using legacy response buffering")
			ngx.ctx.buffered_proxying = true
			kong.ctx.shared.aidr_response_buffering = true
		end
	else
		kong.log.notice("[AIDR-RESPONSE] Not using Kong AI Gateway, skipping")
	end
end

-- ✅ SOLUTION: Use the response phase!
-- This phase runs AFTER the upstream responds but BEFORE sending to client
-- Key advantages:
-- - HTTP calls (cosockets) ARE allowed
-- - Full response body is available
-- - Can modify the response before sending to client
-- - Kong PDK functions work correctly
function CrowdStrikeAIDRResponseHandler:response(config)
	kong.log.notice("[AIDR-RESPONSE] response() phase called")

	-- Only process if using Kong AI Gateway
	if config.upstream_llm.provider ~= "kong" then
		kong.log.notice("[AIDR-RESPONSE] Skipping - not using Kong AI Gateway")
		return
	end

	-- Check if buffering was enabled (use kong.ctx.shared which persists across phases)
	if not kong.ctx.shared.aidr_response_buffering then
		kong.log.notice("[AIDR-RESPONSE] Skipping - buffering not enabled (aidr_response_buffering=" .. tostring(kong.ctx.shared.aidr_response_buffering) .. ")")
		return
	end

	kong.log.notice("[AIDR-RESPONSE] Buffering was enabled, proceeding with inspection")

	local status = kong.response.get_status()
	kong.log.notice("[AIDR-RESPONSE] Response status: " .. status)

	-- Only process successful responses
	if status ~= 200 then
		kong.log.notice("[AIDR-RESPONSE] Skipping AIDR inspection for non-200 response: " .. status)
		return
	end

	-- Get the buffered response body from ai-proxy-advanced
	local body = kong.service.response.get_raw_body()
	kong.log.notice("[AIDR-RESPONSE] Got response body, length: " .. (body and #body or 0))

	if not body or body == "" then
		kong.log.notice("[AIDR-RESPONSE] Empty response body, skipping AIDR inspection")
		return
	end

	-- Check if response is gzip encoded and decompress if needed
	local content_encoding = kong.response.get_header("Content-Encoding")
	if content_encoding == "gzip" then
		kong.log.notice("[AIDR-RESPONSE] Response is gzip encoded, decompressing...")
		local decompressed, err = kong_utils.inflate_gzip(body)
		if not decompressed then
			kong.log.err("[AIDR-RESPONSE] Failed to decompress gzip response: " .. tostring(err))
			return
		end
		body = decompressed
		kong.log.notice("[AIDR-RESPONSE] Decompressed body length: " .. #body)
	end

	-- Log the body for debugging
	kong.log.notice("[AIDR-RESPONSE] Inspecting response with AIDR (body length: " .. #body .. ")")
	kong.log.notice("[AIDR-RESPONSE] Response body preview: " .. string.sub(body, 1, 200))

	-- Validate that body is valid JSON before passing to AIDR
	local test_decode, decode_err = cjson.decode(body)
	if not test_decode then
		kong.log.err("Response body is not valid JSON, skipping AIDR inspection: " .. tostring(decode_err))
		kong.log.err("Body content: " .. body)
		return
	end

	-- ✅ Call AIDR directly - HTTP calls ARE allowed in response phase!
	-- No timers, no workarounds needed
	local success, result = pcall(ai_guard.run_ai_guard, config, "response", body)

	if not success then
		-- Log the error but don't block the response
		kong.log.err("AIDR response inspection failed: " .. tostring(result))
		-- Return the original response to the client
		return
	end

	-- If AIDR returned a modified response, use it
	-- Otherwise, the original response will be returned
	if result ~= nil then
		kong.log.debug("AIDR modified the response, returning updated version")

		-- Parse the result if it's a JSON string
		local response_body
		if type(result) == "string" then
			local decoded, err = cjson.decode(result)
			if decoded then
				response_body = decoded
			else
				kong.log.warn("Failed to decode AIDR response, using as-is: " .. tostring(err))
				response_body = result
			end
		else
			response_body = result
		end

		-- Return the modified response with appropriate status and headers
		return kong.response.exit(200, response_body, {
			["Content-Type"] = "application/json"
		})
	end

	-- If we get here, return the original response (AIDR didn't modify it)
	kong.log.debug("AIDR approved response without modifications")
end

return CrowdStrikeAIDRResponseHandler
