local M = {}
local ts = vim.treesitter
local get_node_text = ts.get_node_text
-----------------------------------------ast-----------------------------------

--- Generate FucntionInfo from declaration
--- @param info FunctionInfo
function M.gen_from_declarator(info)
	local node, _ = M.find_ancestor(info.func, { "function_definition", "declaration", "field_declaration" })
	if not node then
		error("function_declarator have no support parent")
	end
	info.full = node

	M.parse_func_name(info)
end

--- Generate FunctionInfo from declaration
--- @param ctx BufferContext
--- @param query vim.treesitter.Query
function M.gen_from_declaration(ctx, query)
	local info = ctx.info

	for _, match in query:iter_matches(info.full, ctx.buf, 0, -1) do
		for id, nodes in ipairs(match) do
			local cap = query.captures[id]
			if cap == "func" then
				info.func = nodes[1]
			end
		end
	end

	M.parse_func_name(info)
end

---Find an ancestor node whose type matches on of the given types.
---@param node TSNode?
---@param types string[]
---@return TSNode?,string
function M.find_ancestor(node, types)
	while node do
		local type = node:type()
		if vim.tbl_contains(types, type) then
			return node, type
		end
		node = node:parent()
	end
	return nil, ""
end

--- Get buf ts tree root node
---@param buf integer
---@return TSNode
function M.get_root(buf)
	local parser = ts.get_parser(buf, "cpp")
	if not parser then
		error("have not find cpp parser")
	end

	local tree = parser:parse()[1]
	if not tree then
		error("have not find parse tree")
	end

	return tree:root()
end

---search buffer all function name same
---@param ctx RequestContext
---@return TSNode[],integer
function M.search_functions(ctx)
	local full_match_id = 0

	local query = ctx.query.func
	local origin = ctx.origin
	local target = ctx.target
	local root = M.get_root(target.buf)

	local func_nodes = {}
	for index, match in query:iter_matches(root, target.buf, 0, -1) do
		local decl_node

		for id, nodes in ipairs(match) do
			local cap = query.captures[id]
			local node = nodes[1]

			if cap == "func" then
				decl_node = node
			end
		end

		if decl_node then
			local target_ctx = { buf = target.buf, info = { namespace = {}, class = {}, scope = {}, func = decl_node } }
			M.gen_from_declarator(target_ctx.info)
			M.parse_func(target_ctx, ctx.cache)

			local name_same, full_same = M.is_func_same(origin, target_ctx)
			if name_same then
				table.insert(func_nodes, decl_node)
			end
			if full_same then
				full_match_id = index
				target.info = target_ctx.info
			end
		end
	end
	return func_nodes, full_match_id
end

--- Parse definition function name to get class and namespace
-- TODO:
--- there have no capability to perform semantic analysis
---@param info FunctionInfo
function M.parse_func_name(info)
	local func = info.func:field("declarator")[1]
	local type = func:type()

	--- function name
	if type == "identifier" or type == "field_identifier" or type == "operator_name" then
		info.name = func
	elseif type == "qualified_identifier" then
		local node = func
		while type ~= "identifier" and type ~= "operator_name" do
			table.insert(info.scope, node:field("scope")[1])
			node = node:field("name")[1]
			if not node then
				error("find function name failed")
			end
			type = node:type()
		end
		info.name = node
	else
		error("find not support declarator type " .. type)
	end

	--- outer namespace
	local node = info.full:parent()
	while node do
		type = node:type()
		if type == "namespace_definition" then
			local name = node:field("name")[1]
			local name_type = name:type()
			if name_type == "namespace_identifier" then
				table.insert(info.namespace, 1, name)
			elseif name_type == "nested_namespace_specifier" then
				local children = name:named_children()
				for i = #children, 1, -1 do
					table.insert(info.namespace, 1, children[i])
				end
			else
				error("unknown namespace identifier")
			end
		elseif type == "class_specifier" or type == "struct_specifier" then
			table.insert(info.class, 1, node:field("name")[1])
		end
		node = node:parent()
	end
end

---@param origin BufferContext
---@param target BufferContext
---@return boolean,boolean # name_same,full_same
function M.is_func_same(origin, target)
	local name_same = false
	local full_same = false

	-- check function name(with class)
	if not M.is_array_same(origin.buf, origin.info.class, target.buf, target.info.class) then
		return name_same, full_same
	end

	if get_node_text(origin.info.name, origin.buf) ~= get_node_text(target.info.name, target.buf) then
		return name_same, full_same
	end

	name_same = true

	-- check function namespace
	if not M.is_array_same(origin.buf, origin.info.namespace, target.buf, target.info.namespace) then
		return name_same, full_same
	end

	-- check function other part
	local nodes1 = origin.info.func:named_children()
	local nodes2 = target.info.func:named_children()

	if #nodes1 ~= #nodes2 then
		return name_same, full_same
	end

	local name_identifier = { "identifier", "field_identifier", "qualified_identifier" }
	for i = 1, #nodes1 do
		if not vim.tbl_contains(name_identifier, nodes1[i]:type()) then
			if
				not M.is_node_same(
					origin.buf,
					nodes1[i],
					target.buf,
					nodes2[i],
					{ "optional_parameter_declaration" },
					M.handle_ignore
				)
			then
				return name_same, full_same
			end
		end
	end

	full_same = true

	return name_same, full_same
end

--- check node have same node text(ignore some type)
---@param bufnr1 integer
---@param node1 TSNode
---@param bufnr2 integer
---@param node2 TSNode
---@param ignore string[]
---@param func function? handle ignore node
---@return boolean
function M.is_node_same(bufnr1, node1, bufnr2, node2, ignore, func)
	ignore = ignore or {}
	local type1 = node1:type()
	local type2 = node2:type()

	if vim.tbl_contains(ignore, type1) or vim.tbl_contains(ignore, type2) then
		if func then
			return func(bufnr1, node1, bufnr2, node2)
		end
		return true
	end

	if type1 ~= type2 then
		return false
	end

	local children1 = node1:named_children()
	local children2 = node2:named_children()

	local num = #children1

	if num ~= #children2 then
		return false
	end

	if num == 0 then
		return get_node_text(node1, bufnr1) == get_node_text(node2, bufnr2)
	end

	for i = 1, num do
		local child1 = children1[i]
		local child2 = children2[i]
		if not M.is_node_same(bufnr1, child1, bufnr2, child2, ignore, func) then
			return false
		end
	end

	return true
end

--- handle ignore node
---@param bufnr1 integer
---@param node1 TSNode
---@param bufnr2 integer
---@param node2 TSNode
---@return boolean
function M.handle_ignore(bufnr1, node1, bufnr2, node2)
	local children1 = M.param_named_children(node1)
	local children2 = M.param_named_children(node2)

	for i = 1, #children1 do
		local child1 = children1[i]
		local child2 = children2[i]
		if get_node_text(child1, bufnr1) ~= get_node_text(child2, bufnr2) then
			return false
		end
	end
	return true
end

--- Return a list of nodes named children (remove option param default_value)
---@param node TSNode
---@return TSNode[]
function M.param_named_children(node)
	local children = node:named_children()
	if not (node:type() == "optional_parameter_declaration") then
		return children
	end
	local default = node:field("default_value")[1]
	return vim.tbl_filter(function(item)
		return not default:equal(item)
	end, children)
end

--TODD: maybe hvae bug in CRLF text
--- Get row and col offset releative root node
--- Is zero-based
---@param bufnr integer
---@param root TSNode
---@param row integer
---@param col integer
---@return integer
function M.pos_to_offset(bufnr, root, row, col)
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

--- Whether TSNode array is same
---@param bufnr1 integer
---@param array1 TSNode[]
---@param bufnr2 integer
---@param array2 TSNode
---@return boolean
function M.is_array_same(bufnr1, array1, bufnr2, array2)
	if #array1 ~= #array2 then
		return false
	end

	for i = 1, #array1 do
		if get_node_text(array1[i], bufnr1) ~= get_node_text(array2[i], bufnr2) then
			return false
		end
	end
	return true
end

--- Find target have namespace
--- return array what have find
---@param bufnr1 integer ndoes of array buffer handle
---@param names1 TSNode[] namespace names
---@param bufnr2 integer serached buffer handle
---@param root TSNode
---@param query vim.treesitter.Query
---@param index integer
---@param res TSNode[] result array
---@return boolean
function M.find_namespaces(bufnr1, names1, bufnr2, root, query, index, res)
	if #names1 == 0 then
		return false
	end

	for _, match in query:iter_matches(root, bufnr2, 0, -1) do
		local namespace
		local names2 = {}
		local body
		for id, nodes in pairs(match) do
			local cap = query.captures[id]
			if cap == "name" then
				local type = nodes[1]:type()
				if type == "namespace_identifier" then
					table.insert(names2, nodes[1])
				elseif type == "nested_namespace_specifier" then
					vim.list_extend(names2, nodes[1]:named_children())
				else
					error("unknown namespace identifier")
				end
			elseif cap == "namespace" then
				namespace = nodes[1]
			elseif cap == "body" then
				body = nodes[1]
			else
				error("why namespace query have unknown captures")
			end
		end

		local save = index
		-- find in namespace_definition name field
		for _, name in ipairs(names2) do
			if get_node_text(name, bufnr2) == get_node_text(names1[index + 1], bufnr1) then
				table.insert(res, namespace)
				index = index + 1
				if index == #names1 then
					-- names2 is long than names1,
					if #names2 + save > #names1 then
						goto back
					end
					return true
				end
			else
				-- names2 have wrong level,skip this match
				-- remove added node
				goto back
			end
		end

		-- go to here ,have right level prefix,but still find remain
		if M.find_namespaces(bufnr1, names1, bufnr2, body, query, index, res) then
			return true
		else
			goto back
		end

		::back::
		for _ = 1, index - save do
			table.remove(res)
			index = save
		end
	end
	return false
end

--- Find target have namespace
--- return array what have find
---@param bufnr1 integer ndoes of array buffer handle
---@param names1 TSNode[] namespace names
---@param bufnr2 integer serached buffer handle
---@param root TSNode
---@param query vim.treesitter.Query
---@param index integer
---@return boolean
function M.find_class(bufnr1, names1, bufnr2, root, query, index, res)
	for _, match in query:iter_matches(root, bufnr2, 0, -1) do
		local class
		local name
		local body
		for id, nodes in pairs(match) do
			local cap = query.captures[id]
			if cap == "class" then
				class = nodes[1]
			elseif cap == "name" then
				name = nodes[1]
			elseif cap == "body" then
				body = nodes[1]
			else
				error("why namespace query have unknown captures")
			end
		end

		if get_node_text(name, bufnr2) == get_node_text(names1[index + 1], bufnr1) then
			table.insert(res, class)
			index = index + 1

			if index == #names1 then
				return true
			end
		else
			return false
		end

		-- go to here ,have right level prefix,but still find remain
		if M.find_class(bufnr1, names1, bufnr2, body, query, index, res) then
			return true
		else
			table.remove(res)
			index = index - 1
		end
	end

	return false
end

-- TODO: now is text equal,should compair semantic
--- Simple Check string have same text as namespace
---@param buf integer
---@param node TSNode
---@param cache {namespace:TSNode[],class:TSNode[]}
---@return boolean
function M.is_namespace(buf, node, cache)
	return vim.tbl_contains(cache.namespace, ts.get_node_text(node, buf))
end

--- TODO: this funcion should combain with parse_func_name?
--- Simple Parse functio declarator name part
---@param ctx BufferContext
---@param cache {namespace:TSNode[],class:TSNode[]}
function M.parse_func(ctx, cache)
	local buf = ctx.buf
	local info = ctx.info

	if info.func:field("declarator")[1]:type() == "qualified_identifier" then
		for _, node in ipairs(info.scope) do
			if M.is_namespace(buf, node, cache) then
				table.insert(info.namespace, node)
			else
				table.insert(info.class, node)
			end
		end
	end
end
return M
