-- Constants for roles
local AidrRoles = {
	PromptRoleSystem = "system",
	PromptRoleUser = "user",
	PromptRoleLlm = "assistant",
}

---@class JSONMessageMap
---@field messages table
---@field lookup table
---@field tools table?

---@alias PathElement string | integer

---@param self JSONMessageMap
---@param content string
---@param role string
---@param path PathElement[]
---@param pos integer?
local function add_message(self, content, role, path, pos)
	if pos ~= nil then
		table.insert(self.messages, pos, {
			content = content,
			role = role,
		})
		table.insert(self.lookup, pos, path)
	else
		table.insert(self.messages, {
			content = content,
			role = role,
		})
		table.insert(self.lookup, path)
	end
end

local function NewJSONMessageMap()
	return {
		messages = {},
		lookup = {},
		tools = nil,
		add_message = add_message,
	}
end

return {
	AidrRoles = AidrRoles,
	NewJSONMessageMap = NewJSONMessageMap,
}
