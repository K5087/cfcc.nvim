local M = {}
local ast = require("cfcc.ast")

---Get function_declarator from current cursor
---@return TSNode?
function M.current()
	local node = vim.treesitter.get_node({ bufnr = 0 })
	local parent =
		ast.find_ancestor(node, { "function_declarator", "function_definition", "declaration", "field_declaration" })
	if not parent then
		return nil
	end
end

--Get function_declarator node from pos
---@param buf integer
---@param row integer
---@param col integer
---@return TSNode
function M.from_pos(buf, row, col) end

---Get function_declarator nodes form selection
---@retrurn TSNode[]
function M.from_selection() end

return M
