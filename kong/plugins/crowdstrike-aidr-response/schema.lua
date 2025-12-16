local typedefs = require("kong.db.schema.typedefs")
local Schema = require("kong.db.schema")

local translate = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator")

local secret = Schema.define {
	type = "string",
	referenceable = true,
	encrypted = true,
}

local PLUGIN_NAME = "crowdstrike-aidr-response"

local schema = {
	name = PLUGIN_NAME,
	fields = {
		{
			protocols = typedefs.protocols_http,
		},
		{
			config = {
				type = "record",
				fields = {
					{
						ai_guard_api_base_url = {
							type = "string",
							required = false,
							default = "https://api.crowdstrike.com/aidr/aiguard",
							description = "CrowdStrike AIDR API base URL",
						},
					},
					{
						ai_guard_api_key = secret {
							required = true,
							description = "CrowdStrike AIDR API Key",
						},
					},
					{
						upstream_llm = {
							type = "record",
							required = true,
							fields = {
								{
									provider = {
										type = "string",
										required = true,
										description = "Provider name used to translate the LLM request to CrowdStrike AIDR format, e.g. 'openai'",
										one_of = translate.list_available_translators(),
									},
								},
								{
									api_uri = {
										type = "string",
										required = true,
										description = "API URI for the route this plugin is applied to",
									},
								},
							},
							custom_validator = function(value)
								local instance, err = translate.get_translator(value.provider)
								if err ~= nil then
									return nil, err
								end

								local api_uri_transformers = instance[value.api_uri]
								if api_uri_transformers ~= nil and value.api_uri ~= "capabilities" then
									return true
								end

								local allowed_values = {}
								local idx = 0
								for k, _ in pairs(instance) do
									if k ~= "capabilities" then
										idx = idx + 1
										allowed_values[idx] = k
									end
								end

								return nil,
									string.format(
										"For provider '%s' allowed api_uris are '%s'",
										value.provider,
										table.concat(allowed_values, ", ")
									)
							end,
						},
					},
					{
						app_id = {
							type = "string",
							required = false,
							description = "Id of source application/agent",
							default = ngx.null,
						},
					},
					{
						user_id = {
							type = "string",
							required = false,
							description = "User/Service account id/service account",
							default = ngx.null,
						},
					},
					{
						llm_provider = {
							type = "string",
							required = false,
							description = "Underlying LLM provider name (e.g. 'OpenAI', 'Anthropic')",
							default = ngx.null,
						},
					},
					{
						model = {
							type = "string",
							required = false,
							description = "Model used to perform the event (e.g. 'gpt-4')",
							default = ngx.null,
						},
					},
					{
						model_version = {
							type = "string",
							required = false,
							description = "Model version used to perform the event (e.g. '4')",
							default = ngx.null,
						},
					},
					{
						source_location = {
							type = "string",
							required = false,
							description = "Location of user or app or agent",
							default = ngx.null,
						},
					},
					{
						tenant_id = {
							type = "string",
							required = false,
							description = "For gateway-like integrations with multi-tenant support",
							default = ngx.null,
						},
					},
					{
						collector_instance_id = {
							type = "string",
							required = false,
							description = "AIDR collector instance id",
							default = ngx.null,
						},
					},
					{
						extra_info = {
							type = "map",
							required = false,
							description = "Additional metadata as key-value pairs",
							keys = { type = "string" },
							values = { type = "string" },
							default = ngx.null,
						},
					},
				},
			},
		},
	},
}

return schema
