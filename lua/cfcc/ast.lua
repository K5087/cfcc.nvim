local M = {}

---Get Node Text
---@param bufnr integer
---@param node TSNode
---@return string
function M.node_text(bufnr, node)
	return vim.treesitter.get_node_text(node, bufnr)
end

--- find parent node that node::type()==type
---@param node TSNode
---@param type string
---@return TSNode?
function M.FindTypeNode(node, type)
	---@type TSNode?
	local cnode = node
	while cnode do
		if cnode:type() == type then
			return cnode
		end
		cnode = cnode:parent()
	end
	return nil
end

---@class FunctionInfo
---@field func TSNode
---@field type TSNode
---@field class TSNode?
---@field namespace TSNode?
---@field is_declarator boolean
---@field full TSNode?

---Get current cursor Function Signature
---@param node TSNode
---@return FunctionInfo?
function M.GetFunctionSign(node)
	local info = {}
	local fnode = M.FindTypeNode(node, "function_declarator")
	if node then
		info.is_declarator = true
	else
		fnode = M.FindTypeNode(node, "function_definition")
		if fnode then
			info.is_declarator = false
		else
			return nil
		end
	end

	info.func = fnode
	info.name = info.func:field("declarator")[1]
	info.params = M.get_function_param_list(info.func)
	local type = info.func:type()

	---@type TSNode?
	local rnode = info.func:parent()
	while rnode ~= nil do
		type = rnode:type()
		if type == "function_definition" then
			info.is_declarator = false
		end
		if type == "declaration" or type == "field_declaration" or type == "function_definition" then
			info.full = rnode
			info.type = rnode:field("type")[1]
			rnode = rnode:parent()
			while rnode ~= nil do
				type = rnode:type()
				if type == "namespace_definition" then
					info.namespace = rnode
				elseif type == "class_specifier" or type == "struct_specifier" then
					info.class = rnode
				end
				rnode = rnode:parent()
			end
			break
		end

		rnode = rnode:parent()
	end
	return info
end

---@class MatchFuncInfo
---@field name boolean whether function name is equal
---@field params boolean whether function params are equal

---search buffer all function name same
---@param bufnr integer
---@param info NodeInfo
---@return TSNode[],integer
function M.search_function(bufnr, info)
	local full_match_id = 0
	local query = vim.treesitter.query.get("cpp", "function_decls")
	if not query then
		vim.notify("can not find function_decl query")
		return {}, full_match_id
	end
	local parser = vim.treesitter.get_parser(bufnr, "cpp")

	if not parser then
		vim.notify("have not find cpp parser")
		return {}, full_match_id
	end

	local tree = parser:parse()[1]

	if not tree then
		vim.notify("have not find parse tree")
		return {}, full_match_id
	end
	local root = tree:root()

	local func_nodes = {}
	for _, match in query:iter_matches(root, bufnr, 0, -1) do
		local decl_node

		for id, nodes in ipairs(match) do
			local cap = query.captures[id]
			local node = nodes[1]

			if cap == "func" then
				decl_node = node
			end
		end

		if decl_node then
			local match_info = M.is_function_equal(info, { bufnr = bufnr, node = decl_node })
			if match_info.name == true then
				table.insert(func_nodes, decl_node)
			end
			if match_info.params == true then
				full_match_id = #func_nodes
			end
		end
	end
	return func_nodes, full_match_id
end

---Get Function Parameter List Node
---@param node TSNode function_declarator
---@return TSNode[]
function M.get_function_param_list(node)
	local param_node = node:field("parameters")[1]

	local params = {}
	for child in param_node:iter_children() do
		table.insert(params, child)
	end
	return params
end

---@class NodeInfo
---@field bufnr integer
---@field node TSNode

---check node text is equal
---@param info1 NodeInfo
---@param info2 NodeInfo
local function is_node_equal(info1, info2)
	return vim.treesitter.get_node_text(info1.node, info1.bufnr)
		== vim.treesitter.get_node_text(info2.node, info2.bufnr)
end

---check weathure tow function_declarator node are equal
---@param info1 NodeInfo function_declarator
---@param info2 NodeInfo function_declarator
---@return MatchFuncInfo
function M.is_function_equal(info1, info2)
	local match_info = {
		name = false,
		params = false,
	}
	local decl_node1 = info1.node:field("declarator")[1]
	local decl_node2 = info2.node:field("declarator")[1]

	if
		is_node_equal({ bufnr = info1.bufnr, node = decl_node1 }, { bufnr = info2.bufnr, node = decl_node2 }) == true
	then
		match_info.name = true
	end

	local params1 = M.get_function_param_list(info1.node)
	local params2 = M.get_function_param_list(info2.node)

	if #params1 ~= #params2 then
		return match_info
	end

	for i = 1, #params1 do
		local type_info1 = {
			bufnr = info1.bufnr,
			node = params1[i],
		}
		if not params2[i] then
			match_info.params = false
			break
		end
		local type_info2 = {
			bufnr = info2.bufnr,
			node = params2[i],
		}

		if is_node_equal(type_info1, type_info2) == true then
			match_info.params = true
			break
		end
	end
	return match_info
end

--TODD: maybe hvae bug in CRLF text
local function pos_to_offset(bufnr, root, row, col)
	local rs, cs = root:start()
	local lines = vim.api.nvim_buf_get_lines(bufnr, rs, row + 1, false)

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

---@class DeleteParamHelp which nodes that between last and end should be delete (just for lsp help)
---@field last TSNode  last keep node
---@field final TSNode end node

---get a array that all optional_parameter_declaration node default should delete
---@param bufnr integer
---@param full TSNode  declaration / field_declaration / function_definition
---@param func TSNode function_declarator
function M.get_del_optparam_ranges2(bufnr, full, func)
	---@type DeleteParamHelp[]
	local optional_param_nodes = {}
	local query = vim.treesitter.query.get("cpp", "optional_parameter_declaration")
	if not query then
		vim.notify("can not find optional_parameter_declaration query")
		return {}
	end
	for _, match in query:iter_matches(full, bufnr, 0, -1) do
		local param = {}
		for id, nodes in ipairs(match) do
			local cap = query.captures[id]
			if cap == "param" then
				param.final = nodes[1]
			elseif cap == "default_value" then
				---@diagnostic disable-next-line
				local last = nodes[1]
				---@diagnostic disable-next-line
				while last:type() ~= "=" do
					---@diagnostic disable-next-line
					last = last:prev_sibling()
				end
				assert(last, "annoying lsp warning")
				param.last = last:prev_sibling()
			end
		end
		table.insert(optional_param_nodes, param)
	end
	table.insert(optional_param_nodes, { last = func, final = full })

	local del_ranges = {}
	for _, nodes in ipairs(optional_param_nodes) do
		-- local l_srow, l_scol, l_erow, l_ecol = nodes.last:range()
		-- local d_srow, d_scol, d_erow, d_ecol = nodes.final:range()
		local _, _, l_erow, l_ecol = nodes.last:range()
		local _, _, d_erow, d_ecol = nodes.final:range()

		-- 0-base, but this is [s,e)
		local s = pos_to_offset(bufnr, full, l_erow, l_ecol)
		local e = pos_to_offset(bufnr, full, d_erow, d_ecol)

		-- convert to lua 1-base,should delete [s+1,e]
		table.insert(del_ranges, {
			s = s + 1,
			e = e,
		})
	end

	return del_ranges
end
return M
