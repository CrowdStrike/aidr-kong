-- Regression test for the openai.lua response translator accepting AI Proxy
-- Advanced-normalized bodies that don't stamp `object == "chat.completion"`.
local translate = require("kong.plugins.crowdstrike-aidr-shared.aidr-translator")

describe("openai translator prepare_chat_completions_response", function()
	local function response_body(object_field)
		return {
			id = "chatcmpl-1",
			object = object_field,
			choices = {
				{ index = 0, message = { role = "assistant", content = "Hi" }, finish_reason = "stop" },
			},
		}
	end

	it("accepts a response body with object == 'chat.completion' (unchanged behavior)", function()
		local instance = translate.get_translator("openai")
		local messages, err = instance["/v1/chat/completions"]["response"](response_body("chat.completion"))

		assert.is_nil(err)
		assert.are.equal(1, #messages.messages)
	end)

	it("accepts an AI Proxy Advanced-normalized body missing `object`", function()
		local instance = translate.get_translator("openai")
		local messages, err = instance["/v1/chat/completions"]["response"](response_body(nil))

		assert.is_nil(err)
		assert.are.equal(1, #messages.messages)
	end)

	it("still rejects a body with no choices at all", function()
		local instance = translate.get_translator("openai")
		local messages, err = instance["/v1/chat/completions"]["response"]({ id = "chatcmpl-1" })

		assert.is_nil(messages)
		assert.are.equal("Invalid response object", err)
	end)
end)
