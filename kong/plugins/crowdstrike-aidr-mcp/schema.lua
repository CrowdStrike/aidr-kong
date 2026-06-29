local typedefs = require("kong.db.schema.typedefs")
local Schema = require("kong.db.schema")

local secret = Schema.define {
	type = "string",
	referenceable = true,
	encrypted = true,
}

local PLUGIN_NAME = "crowdstrike-aidr-mcp"

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
							description = "User or service account identifier",
							default = ngx.null,
						},
					},
					{
						user_name = {
							type = "string",
							required = false,
							description = "Human-readable name of the user or entity initiating the AI interaction (tracked in AIDR as extra_info.user_name)",
							default = ngx.null,
						},
					},
					{
						source_location = {
							type = "string",
							required = false,
							description = "Geographic location of the request origin (e.g. 'US-CA')",
							default = ngx.null,
						},
					},
					{
						tenant_id = {
							type = "string",
							required = false,
							description = "Tenant identifier for multi-tenant deployments",
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
