local typedefs = require("kong.db.schema.typedefs")
local Schema = require("kong.db.schema")

local AVAILABLE_TRANSLATORS = {
	"anthropic",
	"azureai",
	"bedrock",
	"cohere",
	"gemini",
	"kong",
	"openai",
}

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
										one_of = AVAILABLE_TRANSLATORS,
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
								-- api_uri validation against the translator is performed at runtime
								-- in the handler, since the shared translator module is not available
								-- at schema load time in Kong Konnect
								if not value.provider or not value.api_uri then
									return nil, "Both provider and api_uri are required"
								end
								return true
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
