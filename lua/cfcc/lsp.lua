local M = {}
local api = vim.api
local ts = vim.treesitter
local ast = require("cfcc.ast")
local util = require("cfcc.util")

------------------------------------------lsp-----------------------------------------
---check file path whether cpp header
---@param path string file path
---@return boolean
function M.is_header(path)
	local ext = vim.fn.fnamemodify(path, ":e")
	return ext == "h" or ext == "hxx" or ext == "hpp"
end

--- if origin buf is header return uri path,otherwise return header uri
---@param ctx RequestContext
---@param func function (ctx,uri)
function M.get_target(ctx, func)
	local bufnr = ctx.origin.buf
	local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })

	local client = clients[1]
	if not client then
		error("cannot find clangd client")
	end

	local params = vim.lsp.util.make_text_document_params(bufnr)
	---@diagnostic disable-next-line:param-type-mismatch
	client:request("textDocument/switchSourceHeader", params, function(err, result)
		if err then
			error(tostring(err))
		end
		if not result then
			--TODO: have no header/source,should provide a func create file
			error("corresponding file cannot be determined")
		end

		-- func(ctx, result)
		local ok, res = pcall(func, ctx, result)
		if not ok then
			vim.notify(res)
		end
	end, bufnr)
end

---@param ctx RequestContext
function M.have_definition(ctx)
	ast.parse_func(ctx.origin, ctx.cache)

	local funcs, match_id = ast.search_functions(ctx)
	-- vim.print(vim.treesitter.get_node_text(funcs[match_id], ctx.target.buf))
	return match_id ~= 0
end

---create namespace text
---@param buf integer
---@param array TSNode[]
---@param sign_text string[]?
---@return string[]
function M.create_namespace(buf, array, sign_text)
	local text = {}
	local num = #array
	for i = 1, num do
		table.insert(text, string.format("namespace %s {", ts.get_node_text(array[i], buf)))
		table.insert(text, string.format(""))
	end

	if sign_text then
		vim.list_extend(text, sign_text)
	end

	for _ = 1, num do
		table.insert(text, string.format(""))
		table.insert(text, string.format("}"))
	end
	return text
end

--- Generate declarator on header
---@param ctx RequestContext
---@return integer row # cursor should in row
---@return integer col # cursor should in col
function M.gen_declarator_on_header(ctx)
	local origin = ctx.origin
	local buf = ctx.target.buf

	local row, col
	local text = { "" }
	local sign_text = vim.split(M.gen_decl_from_def(origin), "\n", {
		plain = true,
		trimempty = true,
	})

	local root = ast.get_root(buf)

	---@type TSNode[]
	local name_nodes = {}
	local namespace = origin.info.namespace
	local find_name = ast.find_namespaces(origin.buf, namespace, buf, root, ctx.query.namespace, 0, name_nodes)
	local num = #name_nodes

	if find_name then
		root = name_nodes[num]:field("body")[1]
	end

	---@type TSNode[]
	local class_nodes = {}
	local class = origin.info.class
	local find_class = ast.find_class(origin.buf, class, buf, root, ctx.query.class, 0, class_nodes)

	if num > 0 then
		if find_name then
			if find_class then
				table.insert(text, "")
				local body = class_nodes[#class_nodes]:field("body")[1]
				_, _, row, col = body:range()
				col = col - 1
				vim.list_extend(text, sign_text)
				table.insert(text, "")
			else
				error("this is a problem ,need to solve,how to know a scope_identifier is class or namespace")
			end
		else
			error("this is a problem ,need to solve,how to know a scope_identifier is class or namespace")
		end
	else
		if find_class then
			table.insert(text, "")
			local body = class_nodes[#class_nodes]:field("body")[1]
			_, _, row, col = body:range()
			col = col - 1
			vim.list_extend(text, sign_text)
			table.insert(text, "")
		else
			error("find class failed")
		end
	end

	table.insert(text, "")
	api.nvim_buf_set_text(buf, row, col, row, col, text)
	return row + 1, 0
end

--- Generate definition on source
---@param ctx RequestContext
---@return integer row # cursor should in row
---@return integer col # cursor should in col
function M.gen_definition_on_source(ctx)
	local origin = ctx.origin
	local buf = ctx.target.buf
	local namespace = origin.info.namespace

	local sign_text = vim.split(M.gen_def_from_decl(origin), "\n", {
		plain = true,
		trimempty = true,
	})

	local nodes = {}
	local bool = ast.find_namespaces(origin.buf, namespace, buf, ast.get_root(buf), ctx.query.namespace, 0, nodes)

	local text = { "", "" }
	local row, col

	local num = #nodes
	if num > 0 then
		table.insert(text, "")
		local body = nodes[num]:field("body")[1]
		if not bool then
			--create no exist namespace
			local array = {}
			for i = num + 1, #namespace do
				table.insert(array, namespace[i])
			end

			vim.list_extend(text, M.create_namespace(origin.buf, array, sign_text))
		else
			vim.list_extend(text, sign_text)
		end

		table.insert(text, "")
		_, _, row, col = body:range()
		col = col - 1
	else
		vim.list_extend(text, M.create_namespace(origin.buf, namespace, sign_text))
		row = api.nvim_buf_line_count(buf)
		row = row > 0 and row - 1 or 0
		col = #(api.nvim_buf_get_lines(buf, -2, -1, false)[1] or "")
	end

	table.insert(text, "")
	api.nvim_buf_set_text(buf, row, col, row, col, text)
	return row + #text, 0
end

--gen declarator form definition
---@param ctx BufferContext
---@return string
function M.gen_decl_from_def(ctx)
	local buf = ctx.buf
	local info = ctx.info

	local declaration = ts.get_node_text(info.full, buf)
	local del_ranges = util.get_del_optparam_ranges(buf, info.full, info.func)
	table.insert(del_ranges, util.get_delete_range(buf, { last = info.func, final = info.full }, info.full))

	local s_row, s_col = info.func:field("declarator")[1]:range()
	local n_row, n_col = info.name:range()
	table.insert(del_ranges, {
		s = util.pos_to_offset(buf, info.full, s_row, s_col) + 1,
		e = util.pos_to_offset(buf, info.full, n_row, n_col),
	})

	-- delete text from line end
	table.sort(del_ranges, function(a, b)
		return a.s > b.s
	end)

	for _, r in ipairs(del_ranges) do
		-- get [1,s-1]  [e+1,$]
		declaration = declaration:sub(1, r.s - 1) .. declaration:sub(r.e + 1)
	end
	return declaration .. ";"
end

--TODO: this function can have more simple way
--gen definition from declarator
---@param ctx BufferContext
---@return string
function M.gen_def_from_decl(ctx)
	local buf = ctx.buf
	local info = ctx.info

	local declaration = ts.get_node_text(info.full, buf)
	local del_ranges = util.get_del_optparam_ranges(buf, info.full, info.func)
	table.insert(del_ranges, util.get_delete_range(buf, { last = info.func, final = info.full }, info.full))

	-- delete text from line end
	table.sort(del_ranges, function(a, b)
		return a.s > b.s
	end)

	for _, r in ipairs(del_ranges) do
		-- get [1,s-1]  [e+1,$]
		declaration = declaration:sub(1, r.s - 1) .. declaration:sub(r.e + 1)
	end

	if #info.class > 0 then
		local array = {}
		for i = 1, #info.class do
			local class = info.class[i]
			table.insert(array, ts.get_node_text(class, buf))
		end
		local name = table.concat(array, "::")
		local row, col = info.func:range()
		local pos = ast.pos_to_offset(buf, info.full, row, col)
		declaration = declaration:sub(1, pos) .. name .. "::" .. declaration:sub(pos + 1)
	end

	declaration = declaration .. "{\n\n}"

	--remove static inline constexpr and some other keyword
	local type = info.full:field("type")[1]
	if type then
		local s_row, s_col, _, _ = type:range()
		local l_row, l_col = info.full:start()
		local s = ast.pos_to_offset(buf, info.full, l_row, l_col) + 1
		local e = ast.pos_to_offset(buf, info.full, s_row, s_col)

		declaration = declaration:sub(1, s - 1) .. declaration:sub(e + 1)
	else
		local s_row, s_col, _, _ = info.func:range()
		local l_row, l_col = info.full:start()
		local s = ast.pos_to_offset(buf, info.full, l_row, l_col) + 1
		local e = ast.pos_to_offset(buf, info.full, s_row, s_col)

		declaration = declaration:sub(1, s - 1) .. declaration:sub(e + 1)
	end

	return declaration
end

--- Simple analysis class and namespace
---@param buf integer
---@param class_query vim.treesitter.Query
---@param namespace_query vim.treesitter.Query
---@return {namespace: TSNode[], class: TSNode[]}
function M.simple_analysis(buf, class_query, namespace_query)
	local cache = { class = {}, namespace = {} }
	local root = ast.get_root(buf)

	for _, match in class_query:iter_matches(root, buf, 0, -1) do
		for id, nodes in pairs(match) do
			local cap = class_query.captures[id]
			if cap == "name" then
				table.insert(cache.class, ts.get_node_text(nodes[1], buf))
			end
		end
	end
	for _, match in namespace_query:iter_matches(root, buf, 0, -1) do
		for id, nodes in pairs(match) do
			local cap = namespace_query.captures[id]
			if cap == "name" then
				local type = nodes[1]:type()
				if type == "namespace_identifier" then
					table.insert(cache.namespace, ts.get_node_text(nodes[1], buf))
				elseif type == "nested_namespace_specifier" then
					for _, node in ipairs(nodes[1]:named_children()) do
						table.insert(cache.namespace, ts.get_node_text(node, buf))
					end
				end
			end
		end
	end

	return cache
end

return M
