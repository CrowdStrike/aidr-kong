-- FieldMapping represents a mapping between CrowdStrike AIDR and input fields
local FieldMapping = {
	PangeaPath = "", -- Path in Pangea response
	InputPath = "", -- Path in original input
}

-- PangeaAiInput represents the input structure for CrowdStrike AIDR AI input
local PangeaAiInput = {
	messages = {}, -- Array of messages
	model = "", -- Model name
	version = "", -- Model version
}

-- Constants for roles
local AidrRoles = {
	PromptRoleSystem = "system",
	PromptRoleUser = "user",
	PromptRoleLlm = "assistant",
}

-- Helper function to create a new FieldMapping
function FieldMapping.new(pangea_path, input_path)
	return {
		PangeaPath = pangea_path,
		InputPath = input_path,
	}
end

-- Helper function to create a new PangeaAiInput
function PangeaAiInput.new(messages, model, version)
	return {
		messages = messages or {},
		model = model or "",
		version = version or "",
	}
end

---@class JSONMessageMap
local JSONMessageMap = {
	messages = {},
	lookup = {},
	tools = nil, -- Optional: array of tool definitions in AIDR/OpenAI format
}

---@alias PathElement string | integer

---@param content string
---@param role string
---@param path PathElement[]
---@param pos integer?
function JSONMessageMap:add_message(content, role, path, pos)
	if pos ~= nil then
		-- TODO: Remove the "content" field -- we should be able to pass in the original table and the path instead
		-- Getting the content from the path instead seems a bit more robust to me
		table.insert(self.messages, pos, {
			content = content,
			role = role,
		})
		table.insert(self.lookup, pos, path)
	else
		-- TODO: Remove the "content" field -- we should be able to pass in the original table and the path instead
		-- Getting the content from the path instead seems a bit more robust to me
		table.insert(self.messages, {
			content = content,
			role = role,
		})
		table.insert(self.lookup, path)
	end
end

-- TODO: I think this is a bit funky, but it's the most straight forward way I found to
-- keep my type-checker happy
--
-- The method is assigned to the instance instead of using setmetatable(self, { __index = JSONMessageMap }).
-- Kong's streamed custom plugin sandbox (for example on a Konnect-managed data plane) does not expose
-- `setmetatable`, and a managed data plane cannot allow it through KONG_UNTRUSTED_LUA_SANDBOX_ENVIRONMENT.
local function NewJSONMessageMap()
	return {
		messages = {},
		lookup = {},
		tools = nil,
		add_message = JSONMessageMap.add_message,
	}
end

return {
	FieldMapping = FieldMapping,
	PangeaAiInput = PangeaAiInput,
	AidrRoles = AidrRoles,
	NewJSONMessageMap = NewJSONMessageMap,
}
