local M = {}
local api = vim.api
local ts = vim.treesitter
local ast = require("cfcc.ast")

---check function type is declarator or definition
---@param info FunctionInfo
---@return boolean
function M.is_declarator(info)
	return info.full:type() ~= "function_definition"
end

--- Get plugin query
---@param ctx RequestContext
function M.load_query(ctx)
	ctx.query.func = assert(ts.query.get("cpp", "function_decls"), "load function_decl query file failed")
	ctx.query.namesapce = assert(ts.query.get("cpp", "namespace"), "load namespace query file failed")
end

--- Generate RequestContext form current cursor
--- @return  RequestContext
function M.current()
	--- @type RequestContext
	---@diagnostic disable: missing-fields
	local ctx = {
		origin = {
			info = { namespace = {}, class = {} },
		},
		target = {
			info = { namespace = {}, class = {} },
		},
	}
	---@diagnostic enable: missing-fields
	M.load_query(ctx)

	local origin = ctx.origin
	local info = origin.info
	origin.buf = api.nvim_get_current_buf()
	local node = ts.get_node({ bufnr = ctx.origin.buf })

	local parent, type =
		ast.find_ancestor(node, { "function_declarator", "function_definition", "declaration", "field_declaration" })
	if not parent then
		error("can't find function declarator under cursor")
	end

	if type == "function_declarator" then
		info.func = parent
		ast.gen_from_declarator(info)
	else
		info.full = parent
		ast.gen_from_declaration(origin, ctx.query.func)
	end

	return ctx
end

return M
