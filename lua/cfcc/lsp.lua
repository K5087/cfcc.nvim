local M = {}
local ast = require("cfcc.ast")
local ts = vim.treesitter
local debug = require("cfcc.debug")
local api = vim.api
local util = require("cfcc.util")

------------------------------------------lsp-----------------------------------------
---check file path whether cpp header
---@param path string file path
---@return boolean
function M.is_header(path)
	local ext = vim.fn.fnamemodify(path, ":e")
	return ext == "h" or ext == "hxx"
end

--- if origin buf is header return uri path,otherwise return header uri
---@param ctx RequestContext
---@param func function (ctx,uri)
function M.get_target(ctx, func)
	local bufnr = ctx.origin.buf
	local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })
	if #clients < 1 then
		error("cannot find clangd client")
	end

	local client = clients[1]
	local params = vim.lsp.util.make_text_document_params(bufnr)
	---@diagnostic disable-next-line:param-type-mismatch
	client:request("textDocument/switchSourceHeader", params, function(err, result)
		if err then
			error(tostring(err))
		end
		if not result then
			error("corresponding file cannot be determined")
		end

		local ok, res = pcall(func, ctx, result)
		if not ok then
			vim.notify(res)
		end
	end, bufnr)
end

---@param ctx RequestContext
function M.have_definition(ctx)
	local funcs, match_id = ast.search_functions(ctx)
	-- vim.print(vim.treesitter.get_node_text(funcs[match_id], ctx.target.buf))
	return match_id ~= 0
end

---create namespace text
---@param buf integer
---@param array TSNode
---@param insert string[]?
---@return string[]
function M.create_namespace(buf, array, insert)
	local text = {}
	local num = #array
	for i = 1, num do
		table.insert(text, string.format("namespace %s {", ts.get_node_text(array[i], buf)))
		table.insert(text, string.format(""))
	end

	if insert then
		vim.list_extend(text, insert)
	end

	for _ = 1, num do
		table.insert(text, string.format(""))
		table.insert(text, string.format("}"))
	end
	return text
end

--- Generate declarator on header
---@param ctx RequestContext
function M.gen_declarator_on_header(ctx)
	local origin = ctx.origin
	local buf = ctx.target.buf

	local row, col
	local text = { "" }
	local sign_text = M.gen_func_text(origin)

	local root = ast.get_root(buf)

	---@type TSNode[]
	local name_nodes = {}
	local namespace = ctx.origin.info.namespace
	local find_name = ast.find_namespaces(origin.buf, namespace, buf, root, ctx.query.namespace, 0, name_nodes)
	local num = #name_nodes

	if find_name then
		root = name_nodes[num]:field("body")[1]
	end

	---@type TSNode[]
	local class_nodes = {}
	local class = ctx.origin.info.class
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
				error("this is a bud ,need to solve,how to know a scope_identifier is class or namespace")
			end
		else
			error("this is a bud ,need to solve,how to know a scope_identifier is class or namespace")
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
	vim.print(text)
	vim.api.nvim_buf_set_text(buf, row, col, row, col, text)
end

--- Generate definition on source
---@param ctx RequestContext
function M.gen_definition_on_source(ctx)
	local origin = ctx.origin
	local buf = ctx.target.buf
	local namespace = ctx.origin.info.namespace

	local sign_text = M.gen_func_text(origin, { class = true, body = true })

	local nodes = {}
	local bool = ast.find_namespaces(origin.buf, namespace, buf, ast.get_root(buf), ctx.query.namespace, 0, nodes)

	local text = { "" }
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
	vim.api.nvim_buf_set_text(buf, row, col, row, col, text)
end

--- generate function signature text
---
--- ```lua
--- lsp.gen_func_text(origin,{
---    class = true, --whether add class declarator
---    body = false, -- whether add function body
--- })
--- ```
---@param ctx BufferContext
---@param opt? { class: boolean, body: boolean }
---@return string[]
function M.gen_func_text(ctx, opt)
	opt = opt or {}
	local buf = ctx.buf
	local info = ctx.info

	local declaration = ts.get_node_text(info.full, buf)
	local del_ranges = ast.get_del_optparam_ranges(buf, info.full, info.func)
	table.insert(del_ranges, util.get_delete_range(buf, { last = info.func, final = info.full }, info.full))

	-- delete text from line end
	table.sort(del_ranges, function(a, b)
		return a.s > b.s
	end)

	for _, r in ipairs(del_ranges) do
		-- get [1,s-1]  [e+1,$]
		declaration = declaration:sub(1, r.s - 1) .. declaration:sub(r.e + 1)
	end

	if opt.class and #info.class > 0 then
		local array = {}
		for _, class in ipairs(info.class) do
			table.insert(array, ts.get_node_text(class, buf))
		end
		local name = table.concat(array, "::")
		local row, col = info.func:range()
		local pos = ast.pos_to_offset(buf, info.full, row, col)
		declaration = declaration:sub(1, pos) .. name .. "::" .. declaration:sub(pos + 1)
	end

	if opt.body then
		declaration = declaration .. "{\n\n}"
	else
		declaration = declaration .. ";"
	end

	return vim.split(declaration, "\n", {
		plain = true,
		trimempty = true,
	})
end

--gen declarator form definition
---@param ctx BufferContext
---@return string
function M.gen_decl_from_def(ctx)
	local buf = ctx.buf
	local info = ctx.info

	local declaration = ts.get_node_text(info.full, buf)
	local del_ranges = ast.get_del_optparam_ranges(buf, info.full, info.func)
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

--gen definition from declarator
---@param ctx BufferContext
---@return string
function M.gen_def_from_decl(ctx)
	local buf = ctx.buf
	local info = ctx.info

	local declaration = ts.get_node_text(info.full, buf)
	local del_ranges = ast.get_del_optparam_ranges(buf, info.full, info.func)

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
		for _, class in ipairs(info.class) do
			table.insert(array, ts.get_node_text(class, buf))
		end
		local name = table.concat(array, "::")
		local row, col = info.func:range()
		local pos = ast.pos_to_offset(buf, info.full, row, col)
		declaration = declaration:sub(1, pos) .. name .. "::" .. declaration:sub(pos + 1)
	end

	declaration = declaration .. "{\n\n}"
	return declaration
end
return M
