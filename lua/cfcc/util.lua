local M = {}
local api = vim.api
local ts = vim.treesitter
local ast = require("cfcc.ast")

--- Check function type is declarator or definition
---@param info FunctionInfo
---@return boolean
function M.is_declarator(info)
	return info.full:type() ~= "function_definition"
end

--- Get plugin query
---@param ctx RequestContext
function M.load_query(ctx)
	ctx.query.func = assert(ts.query.get("cpp", "function_decls"), "load function_decl query file failed")
	ctx.query.namespace = assert(ts.query.get("cpp", "namespace"), "load namespace query file failed")
	ctx.query.class = assert(ts.query.get("cpp", "class"), "load class query file failed")
end

--- Generate RequestContext form current cursor
--- @return  RequestContext
function M.current()
	--- @type RequestContext
	---@diagnostic disable: missing-fields
	local ctx = {
		origin = {
			info = { namespace = {}, class = {}, scope = {} },
		},
		target = {
			info = { namespace = {}, class = {}, scope = {} },
		},
		query = {},
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
		ast.gen_from_declaration(ctx.origin, ctx.query.func)
	end

	return ctx
end

--- TODD: maybe hvae bug in CRLF text
--- Get row and col offset releative root node
--- Is zero-based
---@param bufnr integer
---@param root TSNode
---@param row integer
---@param col integer
---@return integer
function M.pos_to_offset(bufnr, root, row, col)
	local rs, cs = root:start()
	local lines = api.nvim_buf_get_lines(bufnr, rs, row + 1, false)

	local offset = 0

	for i, line in ipairs(lines) do
		if i == 1 and #lines == 1 then
			offset = offset + (col - cs)
		elseif i == 1 then
			offset = offset + (#line - cs) + 1
		elseif i == #lines then
			offset = offset + col
		else
			offset = offset + #line + 1
		end
	end

	return offset
end

--- Get delete range from node
---@param buf integer
---@param scope {last:TSNode,final:TSNode}
---@param root TSNode releative root node
function M.get_delete_range(buf, scope, root)
	-- local l_srow, l_scol, l_erow, l_ecol = nodes.last:range()
	-- local d_srow, d_scol, d_erow, d_ecol = nodes.final:range()
	local _, _, l_erow, l_ecol = scope.last:range()
	local _, _, f_erow, f_ecol = scope.final:range()

	-- 0-base, but this is [s,e)
	local s = ast.pos_to_offset(buf, root, l_erow, l_ecol)
	local e = ast.pos_to_offset(buf, root, f_erow, f_ecol)

	-- convert to lua 1-base,should delete [s+1,e]
	return {
		s = s + 1,
		e = e,
	}
end

--- Get a array that all optional_parameter_declaration node default should delete
---@param buf integer
---@param full TSNode  declaration / field_declaration / function_definition
---@param func TSNode function_declarator
function M.get_del_optparam_ranges(buf, full, func)
	local query = vim.treesitter.query.get("cpp", "optional_parameter_declaration")

	if not query then
		error("can not find optional_parameter_declaration query")
	end

	local del_ranges = {}
	for _, match in query:iter_matches(full, buf, 0, -1) do
		local param = {}
		for id, nodes in pairs(match) do
			local cap = query.captures[id]
			if cap == "param" then
				param.final = nodes[1]
			elseif cap == "default_value" then
				param.last = nodes[1]:prev_named_sibling()
			end
		end

		table.insert(del_ranges, M.get_delete_range(buf, param, full))
	end

	return del_ranges
end

return M
