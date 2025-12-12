local cjson = require("cjson.safe")
local http = require("resty.http")
local translate = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator")

local internalError = {
	status = "Internal server error",
}

local AIGuard = {}


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

	local transformer = translator_instance[config.upstream_llm.api_uri]
	if transformer == nil then
		kong.log.debug(
			string.format(
				"Could not find transformer for provider '%s' for upstream uri '%s'",
				config.upstream_llm.provider,
				config.upstream_llm.api_uri
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

function AIGuard.get_aidr_fields(config, mode)
  local body = {}

  -- Required fields
  body.source_ip = kong.client.get_forwarded_ip()
  body.event_type = mode == "request" and "input" or "output"

  -- Optional fields from config
  if config.app_id then
    body.app_id = config.app_id
  end

  if config.user_id then
    body.user_id = config.user_id
  end

  if config.llm_provider then
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

  if config.model then
    body.model = config.model
  end

  if config.model_version then
    body.model_version = config.model_version
  end

  if config.source_location then
    body.source_location = config.source_location
  end

  if config.tenant_id then
    body.tenant_id = config.tenant_id
  end

  if config.collector_instance_id then
    body.collector_instance_id = config.collector_instance_id
  end

  -- Build extra_info object
  local service = kong.router.get_service()
  body.extra_info = {}
  
  if service and service.name then
    body.extra_info.app_name = service.name
  end

  if config.extra_info then
    -- Merge any additional extra_info from config
    for k, v in pairs(config.extra_info) do
      body.extra_info[k] = v
    end
  end

  return body
end

return AIGuard
