local cjson = require("cjson.safe")
local http = require("resty.http")
local translate = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator")
local ai_plugin_ctx = require("kong.llm.plugin.ctx")

-- Read-only accessor for the framework's shared "_global" ctx (stream_mode, etc.).
local get_global_ctx = ai_plugin_ctx.get_global_accessors("crowdstrike-aidr-response")

-- CrowdStrike AIDR maximum request body size is 1 MiB; cap per-batch HTTP timeout
-- so a slow AIDR endpoint can never pile up background timers on a long stream.
local STREAM_HTTP_TIMEOUT_MS = 10000
local DEFAULT_STREAM_BATCH_SIZE = 20

local internalError = {
	status = "Internal server error",
}

local AIGuard = {}

local function resolve_user_id(config)
  local consumer = kong.client.get_consumer()
  if consumer then
    if consumer.username then
      return consumer.username
    end
    if consumer.custom_id then
      return consumer.custom_id
    end
  end

  local credential = kong.client.get_credential()
  if credential then
    return credential.id
  end

  return config.user_id
end


---@alias mode "request" | "response"

---@param config table plugin config -- response and request plugins share fields
---@param mode mode Are we running on a request or a response object
---@param raw_original_body string
function AIGuard.run_ai_guard(config, mode, raw_original_body)
	local exit_fn = kong.response.exit

	local original_body, err = cjson.decode(raw_original_body)
	if err then
		kong.log.err("Error decoding input body: " .. err)
		local message = {
			status = "Failed to decode JSON body",
			reason = err,
		}
		return exit_fn(400, message)
	end

	local translator_instance, err = translate.get_translator(config.upstream_llm.provider)
	if err ~= nil or translator_instance == nil then
		kong.log.err("Failed to get translator " .. err)
		return exit_fn(500, internalError)
	end

	-- Trim any whitespace that the user may have accidentally included.
	local api_uri = config.upstream_llm.api_uri:gsub("^%s+", ""):gsub("%s+$", "")
	local transformer = translator_instance[api_uri]
	if transformer == nil then
		kong.log.debug(
			string.format(
				"Could not find transformer for provider '%s' for upstream uri '%s'",
				config.upstream_llm.provider,
				api_uri
			)
		)
		return exit_fn(500, internalError)
	end

	---@type JSONMessageMap, string?
	local messages, err = transformer[mode](original_body)
	if err ~= nil then
		kong.log.err("Failed to process message: " .. err)
		return exit_fn(500, internalError)
	end

	-- local ai_guard_request_body = {
	-- 	messages = messages.messages,
	-- 	log_fields = log_fields,
	-- }

  if #messages.messages == 0 then
		kong.log.debug("No messages found, skipping AIDR")
    return
  end

  ---@type string
	local url = config.ai_guard_api_base_url .. "/v1/guard_chat_completions"
  local ai_guard_request_body = {}

  -- Build CrowdStrike AIDR request body
  ai_guard_request_body = AIGuard.get_aidr_fields(config, mode)
  ai_guard_request_body.guard_input = {}
  ai_guard_request_body.guard_input.messages = messages.messages
  if messages.tools and #messages.tools > 0 then
    ai_guard_request_body.guard_input.tools = messages.tools
  end

	local raw_ai_guard_request_body, err = cjson.encode(ai_guard_request_body)
	if err then
		kong.log.err("Error decoding request body: " .. err)
		return exit_fn(500, internalError)
	end


	local httpc = http.new()
	local res, err = httpc:request_uri(url, {
		method = "POST",
		body = raw_ai_guard_request_body,
		headers = {
			["Authorization"] = "Bearer " .. config.ai_guard_api_key,
			["Content-Type"] = "application/json",
		},
	})

	if err then
		kong.log.err("Error making request to CrowdStrike AIDR: " .. err)
		return exit_fn(500, internalError)
	end

	if res.status ~= 200 then
		kong.log.err("CrowdStrike AIDR returned error: ", res.status, " ", res.body)
		return exit_fn(500, internalError)
	end

	local response, err = cjson.decode(res.body)
	if err then
		kong.log.err("Error decoding CrowdStrike AIDR response: " .. err)
		return exit_fn(500, internalError)
	end

	if type(response.result) ~= "table" then
		kong.log.err("CrowdStrike AIDR response missing or invalid result field")
		return exit_fn(500, internalError)
	end

	if response.result.blocked then
		local message = {
			status = "Prompt has been rejected by CrowdStrike AIDR",
			reason = response.summary or "Content blocked by AIDR policy",
		}
		-- kong.log.warn("Detected unwanted prompt characteristics: ", name, " ", cjson.encode(response))
		return exit_fn(400, message)
	end

	kong.log.debug("CrowdStrike AIDR: content allowed")

	local capabilities = translator_instance.capabilities or {}

	-- By default, we assume we _can_ redact, unless its been explicitly disabled
	local can_redact = capabilities.redaction
	if can_redact == nil then
		can_redact = true
	end

	if not can_redact then
		kong.log.debug("Skipping redaction step")
		return
	end

  if not response.result.transformed then
    return
  end

  -- CrowdStrike AIDR returns guard_output which contains the updated messages
  local guard_output = response.result.guard_output
  if not guard_output or not guard_output.messages then
    kong.log.debug("No guard_output.messages in response, skipping redaction")
    return
  end

  local new_messages = guard_output.messages

	if #new_messages > 0 then
		local new_payload, updated = translate.rewrite_llm_message(original_body, messages, new_messages)
		if updated then
			kong.log.debug("CrowdStrike AIDR: required redaction")
			local raw_new_payload, err = cjson.encode(new_payload)
			if err ~= nil then
				kong.log.err("Failed to encode redacted payload: " .. err)
				return exit_fn(500, internalError)
			end
			return raw_new_payload
		end
	end
end

--- Guard a buffered response body for Kong's Guardrails plugin framework
--- (kong.llm.plugin.guardrail_plugin / shared-filters/guardrails/guard-buffered-response).
--- Unlike run_ai_guard, this never calls kong.response.exit() itself - it returns the
--- {block, block_message, masked, body} contract the framework's guard-buffered-response
--- filter expects, so the framework can apply blocking/masking correctly against the body
--- it read via ai_plugin_ctx.get_response_body() (the AI Proxy Advanced-normalized body,
--- not the raw upstream one).
---@param config table plugin config
---@param raw_body string response body, already normalized to config.upstream_llm's format
---@return table? resp {block, block_message, masked, body}
---@return string? err
function AIGuard.guard_buffered_response(config, raw_body)
	local original_body, err = cjson.decode(raw_body)
	if err then
		return nil, "Failed to decode JSON response body: " .. err
	end

	local translator_instance, err = translate.get_translator(config.upstream_llm.provider)
	if err ~= nil or translator_instance == nil then
		return nil, "Failed to get translator: " .. tostring(err)
	end

	local api_uri = config.upstream_llm.api_uri:gsub("^%s+", ""):gsub("%s+$", "")
	local transformer = translator_instance[api_uri]
	if transformer == nil then
		return nil, string.format(
			"Could not find transformer for provider '%s' for upstream uri '%s'",
			config.upstream_llm.provider,
			api_uri
		)
	end

	---@type JSONMessageMap, string?
	local messages, err = transformer["response"](original_body)
	if err ~= nil then
		return nil, "Failed to process message: " .. err
	end

	if #messages.messages == 0 then
		return { block = false }
	end

	local ai_guard_request_body = AIGuard.get_aidr_fields(config, "response", original_body)
	ai_guard_request_body.guard_input = { messages = messages.messages }
	if messages.tools and #messages.tools > 0 then
		ai_guard_request_body.guard_input.tools = messages.tools
	end

	local raw_ai_guard_request_body, err = cjson.encode(ai_guard_request_body)
	if err then
		return nil, "Error encoding AIDR request body: " .. err
	end

	local url = config.ai_guard_api_base_url .. "/v1/guard_chat_completions"
	local httpc = http.new()
	local res, err = httpc:request_uri(url, {
		method = "POST",
		body = raw_ai_guard_request_body,
		headers = {
			["Authorization"] = "Bearer " .. config.ai_guard_api_key,
			["Content-Type"] = "application/json",
		},
	})

	if err then
		return nil, "Error making request to CrowdStrike AIDR: " .. err
	end

	if res.status ~= 200 then
		return nil, string.format("CrowdStrike AIDR returned error: %s %s", res.status, res.body)
	end

	local response, err = cjson.decode(res.body)
	if err then
		return nil, "Error decoding CrowdStrike AIDR response: " .. err
	end

	if type(response.result) ~= "table" then
		return nil, "CrowdStrike AIDR response missing or invalid result field"
	end

	if response.result.blocked then
		return {
			block = true,
			block_message = {
				status = "Response has been rejected by CrowdStrike AIDR",
				reason = response.summary or "Content blocked by AIDR policy",
			},
		}
	end

	local capabilities = translator_instance.capabilities or {}
	local can_redact = capabilities.redaction
	if can_redact == nil then
		can_redact = true
	end

	if not can_redact or not response.result.transformed then
		return { block = false }
	end

	local guard_output = response.result.guard_output
	if not guard_output or not guard_output.messages or #guard_output.messages == 0 then
		return { block = false }
	end

	local new_payload, updated = translate.rewrite_llm_message(original_body, messages, guard_output.messages)
	if not updated then
		return { block = false }
	end

	local raw_new_payload, err = cjson.encode(new_payload)
	if err then
		return nil, "Failed to encode redacted payload: " .. err
	end

	return { block = false, masked = true, body = raw_new_payload }
end

--- Extract the assistant token text from a single (OpenAI-normalized) SSE event.
--- Mirrors normalize-sse-chunk's get_token_text: choices[1].delta.content for
--- chat, choices[1].text for legacy completions.
---@param event table decoded SSE `data:` payload
---@return string token text, "" when the frame carries no delta text
local function extract_delta_text(event)
	local first_choice = ((event or {}).choices or {})[1]
	if type(first_choice) ~= "table" then
		return ""
	end
	local token = (first_choice.delta and first_choice.delta.content) or first_choice.text
	return (type(token) == "string" and token) or ""
end

--- Ship one aggregated batch of streamed deltas to CrowdStrike AIDR from a
--- background timer. Best-effort enforcement: the deltas in this batch (and any
--- streamed during the AIDR round-trip) are already on the wire and can't be
--- recalled, but if AIDR flags the batch we call set_blocked() to raise the
--- framework's blocked_by_guard flag. ai-proxy-advanced's normalize-sse-chunk
--- reads that flag and suppresses the REST of the stream, injecting a block
--- message + finish_reason=blocked_by_guard - so the model stops being relayed
--- from this point on. set_blocked is a closure over the request's shared _global
--- ctx table (captured by the caller); it works from the timer because Lua closes
--- over the table by reference even though the timer has its own ngx.ctx.
local function send_stream_batch(base_fields, guard_input, api_base_url, api_key, stream_id, batch_index, set_blocked)
	local body = {}
	for k, v in pairs(base_fields) do
		body[k] = v
	end

	-- Correlate every batch of the same stream so CrowdStrike can reassemble the
	-- full response. Clone extra_info so per-batch keys never leak between timers.
	local extra = {}
	if type(base_fields.extra_info) == "table" then
		for k, v in pairs(base_fields.extra_info) do
			extra[k] = v
		end
	end
	extra.stream_id = stream_id
	extra.stream_batch_index = tostring(batch_index)
	body.extra_info = extra
	body.guard_input = guard_input

	local raw_body, err = cjson.encode(body)
	if err then
		kong.log.err("AIDR stream batch ", stream_id, " #", batch_index, ": failed to encode request body: ", err)
		return
	end

	local url = api_base_url .. "/v1/guard_chat_completions"
	local ok, timer_err = ngx.timer.at(0, function(premature)
		if premature then
			return
		end

		local httpc = http.new()
		httpc:set_timeout(STREAM_HTTP_TIMEOUT_MS)
		local res, req_err = httpc:request_uri(url, {
			method = "POST",
			body = raw_body,
			headers = {
				["Authorization"] = "Bearer " .. api_key,
				["Content-Type"] = "application/json",
			},
		})

		if req_err then
			kong.log.err("AIDR stream batch ", stream_id, " #", batch_index, ": request failed: ", req_err)
			return
		end

		if res.status ~= 200 then
			kong.log.err("AIDR stream batch ", stream_id, " #", batch_index, ": returned ", res.status, " ", res.body)
			return
		end

		local response, decode_err = cjson.decode(res.body)
		if decode_err then
			kong.log.err("AIDR stream batch ", stream_id, " #", batch_index, ": failed to decode response: ", decode_err)
			return
		end

		if type(response.result) == "table" and response.result.blocked then
			local reason = response.summary or "content flagged by AIDR policy"
			-- Abort the rest of the stream: raise blocked_by_guard so normalize-sse-chunk
			-- suppresses all further content and terminates with a block message. Deltas
			-- already sent before this verdict slipped through (the streaming limitation).
			if set_blocked then
				set_blocked("Response blocked by CrowdStrike AIDR policy: " .. reason)
			end
			kong.log.warn(
				"CrowdStrike AIDR flagged streaming response batch ",
				stream_id,
				" #",
				batch_index,
				" - aborting remainder of stream: ",
				reason
			)
		else
			kong.log.debug("CrowdStrike AIDR stream batch ", stream_id, " #", batch_index, " allowed")
		end
	end)

	if not ok then
		kong.log.err("AIDR stream batch ", stream_id, " #", batch_index, ": failed to schedule timer: ", timer_err)
	end
end

--- Flush the current delta buffer as one AIDR batch (no-op when empty).
local function flush_stream_batch(state, conf)
	if state.delta_count == 0 then
		return
	end

	local text = table.concat(state.buf)
	state.buf = {}
	state.delta_count = 0

	if text == "" then
		return
	end

	state.batch_index = state.batch_index + 1
	send_stream_batch(
		state.base_fields,
		{ messages = { { role = "assistant", content = text } } },
		conf.ai_guard_api_base_url,
		conf.ai_guard_api_key,
		state.stream_id,
		state.batch_index,
		state.set_blocked
	)
end

--- Parse one line of SSE, appending any assistant delta to the batch buffer and
--- flushing when the batch reaches its configured size.
local function process_sse_line(state, line, batch_size, conf)
	-- Strip a trailing CR (SSE line terminator is "\r\n" or "\n").
	if line:sub(-1) == "\r" then
		line = line:sub(1, -2)
	end

	local payload = line:match("^data:%s?(.*)$")
	if not payload or payload == "" or payload == "[DONE]" then
		return
	end

	local event, err = cjson.decode(payload)
	if err or type(event) ~= "table" then
		return
	end

	local token = extract_delta_text(event)
	if token == "" then
		return
	end

	state.buf[#state.buf + 1] = token
	state.delta_count = state.delta_count + 1
	state.total_deltas = state.total_deltas + 1

	if state.delta_count >= batch_size then
		flush_stream_batch(state, conf)
	end
end

--- STREAMING-stage entry point (see stream_guard.lua). Runs once per body_filter
--- invocation of an SSE response. Buffers SSE deltas into batches of
--- conf.stream_batch_size and fires each batch off to CrowdStrike AIDR in the
--- background. This filter itself never touches ngx.arg; enforcement is
--- best-effort - if a batch is flagged, the background timer raises
--- blocked_by_guard and ai-proxy-advanced's normalize-sse-chunk suppresses the
--- remainder of the stream. Deltas already sent before the verdict slip through.
---@param conf table plugin config
---@return boolean always true
function AIGuard.guard_stream_response(conf)
	if conf.guard_streaming_response == false then
		return true
	end

	-- Only inspect a real, streamed 200 from the upstream service. stream_mode is
	-- set by ai-proxy-advanced's normalize-request filter; if it isn't set we
	-- aren't on an AI Gateway streaming route, so there is nothing to do.
	if kong.response.get_source() ~= "service"
		or kong.service.response.get_status() ~= 200
		or not get_global_ctx("stream_mode")
	then
		return true
	end

	local state = kong.ctx.plugin.aidr_stream
	if not state then
		-- First chunk: capture everything the background timers will need while we
		-- still have a request context to read it from.
		local model
		if ai_plugin_ctx.has_namespace("normalize-sse-chunk") then
			model = ai_plugin_ctx.get_namespaced_ctx("normalize-sse-chunk", "response_model")
		end

		-- Capture the request's shared _global ctx table by reference so a background
		-- timer can raise blocked_by_guard on it (normalize-sse-chunk reads it from
		-- the same table to abort the rest of the stream).
		ngx.ctx.ai_namespaced_ctx = ngx.ctx.ai_namespaced_ctx or {}
		ngx.ctx.ai_namespaced_ctx["_global"] = ngx.ctx.ai_namespaced_ctx["_global"] or {}
		local global_ctx = ngx.ctx.ai_namespaced_ctx["_global"]

		state = {
			stream_id = kong.request.get_id(),
			batch_index = 0,
			delta_count = 0,
			total_deltas = 0,
			buf = {},
			partial = "",
			base_fields = AIGuard.get_aidr_fields(conf, "response", model and { model = model } or nil),
			global_ctx = global_ctx,
			set_blocked = function(msg)
				global_ctx.blocked_by_guard = msg
			end,
		}
		kong.ctx.plugin.aidr_stream = state
	end

	-- Once a prior batch's verdict aborted the stream, stop inspecting/dispatching:
	-- normalize-sse-chunk is already suppressing the remaining frames.
	if state.global_ctx.blocked_by_guard then
		return true
	end

	local batch_size = conf.stream_batch_size or DEFAULT_STREAM_BATCH_SIZE
	local chunk = ngx.arg[1]

	if type(chunk) == "string" and chunk ~= "" then
		-- SSE events can straddle body_filter boundaries; carry the trailing
		-- partial line forward and only parse complete lines.
		local data = state.partial .. chunk
		local start = 1
		while true do
			local nl = data:find("\n", start, true)
			if not nl then
				state.partial = data:sub(start)
				break
			end
			process_sse_line(state, data:sub(start, nl - 1), batch_size, conf)
			start = nl + 1
		end
	end

	if ngx.arg[2] then
		-- End of stream: parse any dangling partial line and flush the remainder
		-- as a final (possibly < batch_size) batch.
		if state.partial ~= "" then
			process_sse_line(state, state.partial, batch_size, conf)
			state.partial = ""
		end
		flush_stream_batch(state, conf)

		-- Positive, default-visible confirmation that this streamed response was
		-- inspected. One line per streaming request. Per-batch outcomes (allowed /
		-- flagged / errored) are logged from the background timers at debug/warn/err.
		kong.log.notice(
			"CrowdStrike AIDR: inspected streaming response for stream ",
			state.stream_id,
			" - dispatched ",
			state.batch_index,
			" batch(es), ",
			state.total_deltas,
			" delta(s)"
		)
	end

	return true
end

function AIGuard.get_aidr_fields(config, mode)
  local body = {}

  -- Required fields
  body.source_ip = kong.client.get_forwarded_ip()
  body.event_type = mode == "request" and "input" or "output"

  -- Optional fields from config
  if config.app_id and config.app_id ~= ngx.null then
    body.app_id = config.app_id
  end

  local user_id = resolve_user_id(config)
  if user_id and user_id ~= ngx.null then
    body.user_id = user_id
  end

  if config.llm_provider and config.llm_provider ~= ngx.null then
    body.llm_provider = config.llm_provider
  elseif config.upstream_llm and config.upstream_llm.provider then
    -- Map provider name to a more standard format
    local provider_map = {
      openai = "OpenAI",
      anthropic = "Anthropic",
      azureai = "Azure OpenAI",
      bedrock = "AWS Bedrock",
      cohere = "Cohere",
      gemini = "Google Gemini",
      kong = "Kong AI Gateway"
    }
    body.llm_provider = provider_map[config.upstream_llm.provider] or config.upstream_llm.provider
  end

  if config.model and config.model ~= ngx.null then
    body.model = config.model
  end

  if config.model_version and config.model_version ~= ngx.null then
    body.model_version = config.model_version
  end

  if config.source_location and config.source_location ~= ngx.null then
    body.source_location = config.source_location
  end

  if config.tenant_id and config.tenant_id ~= ngx.null then
    body.tenant_id = config.tenant_id
  end

  if config.collector_instance_id and config.collector_instance_id ~= ngx.null then
    body.collector_instance_id = config.collector_instance_id
  end

  -- Build extra_info object
  local service = kong.router.get_service()
  body.extra_info = {}

  if service and service.name then
    body.extra_info.app_name = service.name
  end

  if config.extra_info and config.extra_info ~= ngx.null then
    -- Merge any additional extra_info from config
    for k, v in pairs(config.extra_info) do
      body.extra_info[k] = v
    end
  end

  return body
end

return AIGuard
