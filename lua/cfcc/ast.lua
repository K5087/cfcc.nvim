local M = {}
local util = require("cfcc.util")

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

---Get current cursor Function Signature
---@param node TSNode
---@return FunctionInfo?
function M.GetFunctionSign(node)
	local info = {
		namespace = {},
	}
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
					table.insert(info.namespace, rnode:field("name")[1])
				elseif type == "class_specifier" or type == "struct_specifier" then
					info.class = rnode:field("name")[1]
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
---@param bufnr2 integer
---@param bufnr1 integer
---@param info FunctionInfo
---@return TSNode[],integer
function M.search_function(bufnr2, bufnr1, info)
	local full_match_id = 0
	local query = vim.treesitter.query.get("cpp", "function_decls")
	if not query then
		vim.notify("can not find function_decl query")
		return {}, full_match_id
	end
	local parser = vim.treesitter.get_parser(bufnr2, "cpp")

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
	for _, match in query:iter_matches(root, bufnr2, 0, -1) do
		local decl_node

		for id, nodes in ipairs(match) do
			local cap = query.captures[id]
			local node = nodes[1]

			if cap == "func" then
				decl_node = node
			end
		end

		if decl_node then
			--TODO: for same function should not do repeat
			local match_info = M.is_function_equal(
				bufnr1,
				info.func,
				bufnr2,
				decl_node,
				{ namespace = info.namespace, class = info.class }
			)
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

---check node text is equal
---@param bufnr1 integer
---@param node1 TSNode
---@param bufnr2 integer
---@param node2 TSNode
local function is_node_equal(bufnr1, node1, bufnr2, node2)
	return vim.treesitter.get_node_text(node1, bufnr1) == vim.treesitter.get_node_text(node2, bufnr2)
end

---@class NameNodeHelp function name  node help
---@field bufnr integer buffer number
---@field scope TSNode[] namespace_identifier
---@field name TSNode identifier

---generate name node help from function_declarator
---@param node TSNode
---@param class TSNode?
---@param namespace TSNode[]?
---@return NameNodeHelp
local function GetNameNodeHelp(bufnr, node, class, namespace)
	---type NameNodeHelp
	local help = {
		bufnr = bufnr,
		scope = vim.list_extend({}, namespace or {}),
		name = nil,
	}

	local decl_node = node:field("declarator")[1]
	local type = decl_node:type()

	if type == "identifier" or type == "field_identifier" then
		help.name = decl_node
	elseif type == "qualified_identifier" then
		table.insert(help.scope, decl_node:field("scope")[1])
		local name = decl_node:field("name")[1]
		while name:type() ~= "identifier" do
			table.insert(help.scope, name:field("scope")[1])
			name = name:field("name")[1]
		end
		help.name = name
	else
		vim.notify("find not support declarator type " .. type)
		help.name = decl_node
	end

	if class then
		table.insert(help.scope, class)
	end

	return help
end

---is function name help equal
---@param node1 NameNodeHelp
---@param node2 NameNodeHelp
---@param only_check_name boolean whether only check function name
local function is_name_node_equal(node1, node2, only_check_name)
	local bool = is_node_equal(node1.bufnr, node1.name, node2.bufnr, node2.name)

	if not only_check_name then
		if #node1.scope ~= #node2.scope then
			return false
		end
		for i = 1, #node1.scope do
			local scope1 = node1.scope[i]
			local scope2 = node2.scope[i]
			if not is_node_equal(node1.bufnr, scope1, node2.bufnr, scope2) then
				return false
			end
		end
	end

	return bool
end

---check weathure tow function_declarator node are equal
---@param bufnr1 integer
---@param node1 TSNode function_declarator
---@param bufnr2 integer
---@param node2 TSNode function_declarator
---@param opt {}? for info1,usually a function_declarator from source ,maybe have namespace/class scope,so put them in opts to simple matching
---@return MatchFuncInfo
function M.is_function_equal(bufnr1, node1, bufnr2, node2, opt)
	local match_info = {
		name = false,
		params = false,
	}

	local name_help1
	if opt then
		name_help1 = GetNameNodeHelp(bufnr1, node1, opt.class, opt.namespace)
	else
		name_help1 = GetNameNodeHelp(bufnr1, node1)
	end

	local name_help2 = GetNameNodeHelp(bufnr2, node2)

	match_info.name = is_name_node_equal(name_help1, name_help2, false)

	local params1 = node1:field("parameters")[1]:named_children()
	local params2 = node2:field("parameters")[1]:named_children()

	if #params1 ~= #params2 then
		return match_info
	end

	for i = 1, #params1 do
		if is_node_equal(bufnr1, params1[i], bufnr2, params2[i]) == false then
			return match_info
		end
	end

	match_info.params = true
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
				param.last = nodes[1]:prev_named_sibling()
			end
		end
		table.insert(optional_param_nodes, param)
	end
	-- remove function declarator end of ;
	table.insert(optional_param_nodes, { last = func, final = full })

	local del_ranges = {}
	for _, nodes in ipairs(optional_param_nodes) do
		-- local l_srow, l_scol, l_erow, l_ecol = nodes.last:range()
		-- local d_srow, d_scol, d_erow, d_ecol = nodes.final:range()
		local _, _, l_erow, l_ecol = nodes.last:range()
		local _, _, f_erow, f_ecol = nodes.final:range()

		-- 0-base, but this is [s,e)
		local s = pos_to_offset(bufnr, full, l_erow, l_ecol)
		local e = pos_to_offset(bufnr, full, f_erow, f_ecol)

		-- convert to lua 1-base,should delete [s+1,e]
		table.insert(del_ranges, {
			s = s + 1,
			e = e,
		})
	end

	return del_ranges
end

---Get function info from node
---@param node TSNode function_declarator
---@return is_declarator,FunctionInfo?
function M.get_function_info(node)
	local info = {
		namespace = {},
	}
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
					table.insert(info.namespace, rnode:field("name")[1])
				elseif type == "class_specifier" or type == "struct_specifier" then
					info.class = rnode:field("name")[1]
				end
				rnode = rnode:parent()
			end
			break
		end

		rnode = rnode:parent()
	end
	return info
end

-----------------------------------------ast-----------------------------------
---Find an ancestor node whose type matches on of the given types.
---@param node TSNode?
---@param types string[]
---@return TSNode?
function M.find_ancestor(node, types)
	while node do
		if vim.tbl_contains(types, node:type()) then
			return node
		end
		node = node:parent()
	end
	return nil
end

return M
