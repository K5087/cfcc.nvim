local M = {}
M.func = require("cfcc.function")

---check function type is declarator or definition
---@param info FunctionInfo
---@return boolean
function M.is_declarator(info)
	return info.full:type() ~= "function_definition"
end

return M
