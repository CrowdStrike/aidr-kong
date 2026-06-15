return {
	-- Each test case is described like in annotated example below,
	-- and is designed to the aidr-translate module
	-- Note that many of the upstream request / response formats are identical
	-- to OpenAI -- we don't have a separate test case for them in that scenario
	{
		-- Name of the provider (Optional, will use the 'name' if not provided)
		provider = "openai",

		-- Name of the API to test
		api = "/v1/chat/completions",

		-- Request or response
		type = "request",

		-- (Parsed) JSON input, like what would be passed to the original API
		-- Adding some random fields that aren't used as a sanity check here to make sure they are preserved as well,
		-- but for other tests doesn't need to be the full thing, only the subset used to extract 'messages' from
		body = {
			model = "gpt-4",
			temperature = 0.8,
			top_p = 1,
			messages = {
				{
					role = "system",
					content = "System Message 1",
				},
				{
					role = "user",
					content = {
						{ type = "text", text = "User Message 1" },
						{ type = "text", text = "User Message 2" },
					},
				},
				{
					role = "assistant",
					content = "Assistant Message 1",
				},
			},
		},

		-- The input after the transformed messages are added
		-- Verify that we correctly map message transformations
		-- You can customize how messages are transformed, but by default `Transformed ` is added
		-- to the start of each message
		transformed_body = {
			model = "gpt-4",
			temperature = 0.8,
			top_p = 1,
			messages = {
				{ role = "system", content = "Transformed System Message 1" },
				{
					role = "user",
					content = {
						{ type = "text", text = "Transformed User Message 1" },
						{ type = "text", text = "Transformed User Message 2" },
					},
				},
				{ role = "assistant", content = "Transformed Assistant Message 1" },
			},
		},
	},
	-- OpenAI request with tools: verify tools are extracted and passed to AIDR
	{
		provider = "openai",
		api = "/v1/chat/completions",
		type = "request",
		body = {
			model = "gpt-4",
			messages = {
				{ role = "user", content = "What is the weather in Paris?" },
			},
			tools = {
				{
					type = "function",
					["function"] = {
						name = "get_weather",
						description = "Get current weather for a location.",
						parameters = {
							type = "object",
							properties = {
								location = { type = "string" },
							},
							required = { "location" },
						},
					},
				},
			},
		},
		transformed_body = {
			model = "gpt-4",
			messages = {
				{ role = "user", content = "Transformed What is the weather in Paris?" },
			},
			tools = {
				{
					type = "function",
					["function"] = {
						name = "get_weather",
						description = "Get current weather for a location.",
						parameters = {
							type = "object",
							properties = {
								location = { type = "string" },
							},
							required = { "location" },
						},
					},
				},
			},
		},
		expected_tools = {
			{
				type = "function",
				["function"] = {
					name = "get_weather",
					description = "Get current weather for a location.",
					parameters = {
						type = "object",
						properties = {
							location = { type = "string" },
						},
						required = { "location" },
					},
				},
			},
		},
	},
	{
		provider = "openai",
		api = "/v1/chat/completions",
		type = "response",
		body = {
			id = "chatcmpl-BUhm9e8b1WyYSOdGloNhg7zYLpYEk",
			object = "chat.completion",
			choices = {
				{
					index = 0,
					finish_reason = "stop",
					lobprobs = nil,
					message = {
						role = "assistant",
						content = "Assistant Message 1",
						refusal = nil,
						annotations = {},
					},
				},
				{
					index = 0,
					finish_reason = "stop",
					lobprobs = nil,
					message = {
						role = "assistant",
						content = "Assistant Message 2",
						refusal = nil,
						annotations = {},
					},
				},
			},
		},
		transformed_body = {
			id = "chatcmpl-BUhm9e8b1WyYSOdGloNhg7zYLpYEk",
			object = "chat.completion",
			choices = {
				{
					index = 0,
					finish_reason = "stop",
					lobprobs = nil,
					message = {
						role = "assistant",
						content = "Transformed Assistant Message 1",
						refusal = nil,
						annotations = {},
					},
				},
				{
					index = 0,
					finish_reason = "stop",
					lobprobs = nil,
					message = {
						role = "assistant",
						content = "Transformed Assistant Message 2",
						refusal = nil,
						annotations = {},
					},
				},
			},
		},
	},
	{
		provider = "openai",
		api = "/v1/completions",
		type = "request",
		body = {
			prompt = "User Message 1",
		},
		transformed_body = {
			prompt = "Transformed User Message 1",
		},
	},
	{
		provider = "openai",
		api = "/v1/completions",
		type = "response",
		body = {
			object = "text_completion",
			choices = {
				{
					index = 0,
					text = "Assistant Message 1",
				},
				{
					index = 1,
					text = "Assistant Message 2",
				},
			},
		},
		transformed_body = {
			object = "text_completion",
			choices = {
				{
					index = 0,
					text = "Transformed Assistant Message 1",
				},
				{
					index = 1,
					text = "Transformed Assistant Message 2",
				},
			},
		},
	},
	{
		provider = "anthropic",
		api = "/v1/messages",
		type = "request",
		body = {
			system = "System Message 1",
			messages = {
				{
					role = "user",
					content = "User Message 1",
				},
				{
					role = "assistant",
					content = "Assistant Message 1",
				},
			},
		},
		transformed_body = {
			system = "Transformed System Message 1",
			messages = {
				{
					role = "user",
					content = "Transformed User Message 1",
				},
				{
					role = "assistant",
					content = "Transformed Assistant Message 1",
				},
			},
		},
	},
	-- Anthropic request with tools: verify conversion to AIDR/OpenAI format
	{
		provider = "anthropic",
		api = "/v1/messages",
		type = "request",
		body = {
			system = "System Message 1",
			messages = {
				{ role = "user", content = "What is the weather in Paris?" },
			},
			tools = {
				{
					name = "get_weather",
					description = "Get current weather for a location.",
					input_schema = {
						type = "object",
						properties = {
							location = { type = "string" },
						},
						required = { "location" },
					},
				},
			},
		},
		transformed_body = {
			system = "Transformed System Message 1",
			messages = {
				{ role = "user", content = "Transformed What is the weather in Paris?" },
			},
			tools = {
				{
					name = "get_weather",
					description = "Get current weather for a location.",
					input_schema = {
						type = "object",
						properties = {
							location = { type = "string" },
						},
						required = { "location" },
					},
				},
			},
		},
		expected_tools = {
			{
				type = "function",
				["function"] = {
					name = "get_weather",
					description = "Get current weather for a location.",
					parameters = {
						type = "object",
						properties = {
							location = { type = "string" },
						},
						required = { "location" },
					},
				},
			},
		},
	},
	{
		provider = "anthropic",
		api = "/v1/messages",
		type = "response",
		body = {
			id = "msg_013Zva2CMHLNnXjNJJKqJ2EF",
			container = {
				id = "id",
				expires_at = "2019-12-27T18:11:19.117Z",
			},
			content = {
				{
					citations = {
						{
							cited_text = "cited_text",
							document_index = 0,
							document_title = "document_title",
							end_char_index = 0,
							file_id = "file_id",
							start_char_index = 0,
							type = "char_location",
						},
					},
					text = "Hi! My name is Claude.",
					type = "text",
				},
			},
			model = "claude-opus-4-6",
			role = "assistant",
			stop_details = {
				category = "cyber",
				explanation = "explanation",
				type = "refusal",
			},
			stop_reason = "end_turn",
			stop_sequence = nil,
			type = "message",
			usage = {
				cache_creation = {
					ephemeral_1h_input_tokens = 0,
					ephemeral_5m_input_tokens = 0,
				},
				cache_creation_input_tokens = 2051,
				cache_read_input_tokens = 2051,
				inference_geo = "inference_geo",
				input_tokens = 2095,
				output_tokens = 503,
				server_tool_use = {
					web_fetch_requests = 2,
					web_search_requests = 0,
				},
				service_tier = "standard",
			},
		},
		transformed_body = {
			id = "msg_013Zva2CMHLNnXjNJJKqJ2EF",
			container = {
				id = "id",
				expires_at = "2019-12-27T18:11:19.117Z",
			},
			content = {
				{
					citations = {
						{
							cited_text = "cited_text",
							document_index = 0,
							document_title = "document_title",
							end_char_index = 0,
							file_id = "file_id",
							start_char_index = 0,
							type = "char_location",
						},
					},
					text = "Transformed Hi! My name is Claude.",
					type = "text",
				},
			},
			model = "claude-opus-4-6",
			role = "assistant",
			stop_details = {
				category = "cyber",
				explanation = "explanation",
				type = "refusal",
			},
			stop_reason = "end_turn",
			stop_sequence = nil,
			type = "message",
			usage = {
				cache_creation = {
					ephemeral_1h_input_tokens = 0,
					ephemeral_5m_input_tokens = 0,
				},
				cache_creation_input_tokens = 2051,
				cache_read_input_tokens = 2051,
				inference_geo = "inference_geo",
				input_tokens = 2095,
				output_tokens = 503,
				server_tool_use = {
					web_fetch_requests = 2,
					web_search_requests = 0,
				},
				service_tier = "standard",
			},
		},
	},
	-- kong provider: /llm/v1/chat request (identical format to OpenAI)
	{
		provider = "kong",
		api = "/llm/v1/chat",
		type = "request",
		body = {
			model = "gpt-4o-mini",
			messages = {
				{ role = "system", content = "System Message 1" },
				{ role = "user", content = "User Message 1" },
			},
		},
		transformed_body = {
			model = "gpt-4o-mini",
			messages = {
				{ role = "system", content = "Transformed System Message 1" },
				{ role = "user", content = "Transformed User Message 1" },
			},
		},
	},
	-- kong provider: /llm/v1/chat response — OpenAI upstream (object == "chat.completion")
	-- This is the only response path unit-testable without a live ngx.ctx.
	-- Anthropic and Bedrock upstream paths require Kong's ai-proxy context at
	-- runtime and are covered by integration tests only.
	{
		provider = "kong",
		api = "/llm/v1/chat",
		type = "response",
		body = {
			id = "chatcmpl-test",
			object = "chat.completion",
			choices = {
				{
					index = 0,
					finish_reason = "stop",
					message = { role = "assistant", content = "Assistant Message 1" },
				},
			},
		},
		transformed_body = {
			id = "chatcmpl-test",
			object = "chat.completion",
			choices = {
				{
					index = 0,
					finish_reason = "stop",
					message = { role = "assistant", content = "Transformed Assistant Message 1" },
				},
			},
		},
	},
	{
		provider = "bedrock",
		api = "converse",
		type = "response",
		-- Bedrock Converse API: output is an object {message: {role, content[]}}
		body = {
			output = {
				message = {
					role = "assistant",
					content = {
						{ text = "Assistant Message 1" },
						{ text = "Assistant Message 2" },
					},
				},
			},
			stopReason = "end_turn",
		},
		transformed_body = {
			output = {
				message = {
					role = "assistant",
					content = {
						{ text = "Transformed Assistant Message 1" },
						{ text = "Transformed Assistant Message 2" },
					},
				},
			},
			stopReason = "end_turn",
		},
	},
	{
		provider = "cohere",
		api = "/v2/chat",
		type = "response",
		body = {
			message = {
				content = {
					{
						type = "text",
						role = "assistant",
						text = "Assistant Message 1",
					},
					{
						type = "text",
						role = "assistant",
						text = "Assistant Message 2",
					},
				},
			},
		},
		transformed_body = {
			message = {
				content = {
					{
						type = "text",
						role = "assistant",
						text = "Transformed Assistant Message 1",
					},
					{
						type = "text",
						role = "assistant",
						text = "Transformed Assistant Message 2",
					},
				},
			},
		},
	},
	-- OpenAI multi-turn: assistant tool_calls (no content) + tool result
	-- Verifies: assistant tool_calls message is preserved unchanged (nil lookup),
	-- and tool result string content is rewritten.
	{
		provider = "openai",
		api = "/v1/chat/completions",
		type = "request",
		body = {
			model = "gpt-4",
			messages = {
				{ role = "user", content = "What is the weather in Paris?" },
				{
					role = "assistant",
					tool_calls = {
						{
							id = "call_abc123",
							type = "function",
							["function"] = { name = "get_weather", arguments = '{"location":"Paris"}' },
						},
					},
				},
				{
					role = "tool",
					tool_call_id = "call_abc123",
					content = "The weather in Paris is 18°C and sunny.",
				},
				{ role = "user", content = "Thanks!" },
			},
		},
		-- Custom transform: skip nil-content messages (assistant tool_calls)
		transform_fn = function(message)
			if message.content == nil then
				return { role = message.role, content = nil }
			end
			return { role = message.role, content = "Transformed " .. message.content }
		end,
		transformed_body = {
			model = "gpt-4",
			messages = {
				{ role = "user", content = "Transformed What is the weather in Paris?" },
				-- assistant tool_calls: unchanged (nil lookup skips rewrite)
				{
					role = "assistant",
					tool_calls = {
						{
							id = "call_abc123",
							type = "function",
							["function"] = { name = "get_weather", arguments = '{"location":"Paris"}' },
						},
					},
				},
				{
					role = "tool",
					tool_call_id = "call_abc123",
					content = "Transformed The weather in Paris is 18°C and sunny.",
				},
				{ role = "user", content = "Transformed Thanks!" },
			},
		},
	},
	-- Anthropic multi-turn: tool_result content block (string form)
	-- Verifies: tool_result.content is extracted and rewritten by AIDR.
	{
		provider = "anthropic",
		api = "/v1/messages",
		type = "request",
		body = {
			system = "You are a weather assistant.",
			messages = {
				{ role = "user", content = "What is the weather in Paris?" },
				{
					role = "assistant",
					content = {
						{ type = "text", text = "Let me check." },
						{ type = "tool_use", id = "toolu_abc", name = "get_weather", input = { location = "Paris" } },
					},
				},
				{
					role = "user",
					content = {
						{
							type = "tool_result",
							tool_use_id = "toolu_abc",
							content = "The weather in Paris is 18°C and sunny.",
						},
					},
				},
			},
		},
		transformed_body = {
			system = "Transformed You are a weather assistant.",
			messages = {
				{ role = "user", content = "Transformed What is the weather in Paris?" },
				{
					role = "assistant",
					content = {
						{ type = "text", text = "Transformed Let me check." },
						-- tool_use block: unchanged (no text content)
						{ type = "tool_use", id = "toolu_abc", name = "get_weather", input = { location = "Paris" } },
					},
				},
				{
					role = "user",
					content = {
						{
							type = "tool_result",
							tool_use_id = "toolu_abc",
							content = "Transformed The weather in Paris is 18°C and sunny.",
						},
					},
				},
			},
		},
	},
}
