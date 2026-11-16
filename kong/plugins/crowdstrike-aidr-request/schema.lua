local AVAILABLE_TRANSLATORS = {
	"anthropic",
	"azureai",
	"bedrock",
	"cohere",
	"gemini",
	"kong",
	"openai",
}

return {
	name = "crowdstrike-aidr-request",
	fields = {
		{
			protocols = {
				type = "set",
				required = true,
				default = { "grpc", "grpcs", "http", "https" },
				elements = { type = "string", one_of = { "grpc", "grpcs", "http", "https" } },
			},
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
						ai_guard_api_key = {
							type = "string",
							required = true,
							referenceable = true,
							encrypted = true,
							description = "CrowdStrike AIDR API Key",
						},
					},
					{
						failure_mode = {
							type = "string",
							required = true,
							default = "closed",
							one_of = { "closed", "open" },
							description = "What to do when CrowdStrike AIDR cannot inspect the traffic (e.g. service is unreachable or the payload is too large): 'closed' rejects it, 'open' lets it through",
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
						},
					},
					{
						app_id = {
							type = "string",
							required = false,
							description = "Id of source application/agent",
						},
					},
					{
						user_id = {
							type = "string",
							required = false,
							description = "Static fallback user ID if an authenticated one is not available",
						},
					},
					{
						llm_provider = {
							type = "string",
							required = false,
							description = "Underlying LLM provider name (e.g. 'OpenAI', 'Anthropic')",
						},
					},
					{
						model = {
							type = "string",
							required = false,
							description = "Model used to perform the event (e.g. 'gpt-4')",
						},
					},
					{
						model_version = {
							type = "string",
							required = false,
							description = "Model version used to perform the event (e.g. '4')",
						},
					},
					{
						source_location = {
							type = "string",
							required = false,
							description = "Location of user or app or agent",
						},
					},
					{
						tenant_id = {
							type = "string",
							required = false,
							description = "For gateway-like integrations with multi-tenant support",
						},
					},
					{
						collector_instance_id = {
							type = "string",
							required = false,
							description = "AIDR collector instance id",
						},
					},
					{
						extra_info = {
							type = "map",
							required = false,
							description = "Additional metadata as key-value pairs",
							keys = { type = "string" },
							values = { type = "string" },
						},
					},
				},
			},
		},
	},
}
