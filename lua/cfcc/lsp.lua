local M = {}
local ast = require("cfcc.ast")
local ts = vim.treesitter
local debug = require("cfcc.debug")

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
	vim.print(tostring(match_id))
	return match_id ~= 0
end
--- Generate declarator on header
---@param ctx RequestContext
function M.gen_declarator_on_header(ctx)
	local sign_text = M.gen_func_text(ctx.origin)
	vim.print(sign_text)
end
--- Generate definition on source
---@param ctx RequestContext
function M.gen_definition_on_source(ctx)
	local sign_text = M.gen_func_text(ctx.origin)

	ast.find_namespace(ctx.origin.buf, ctx.origin.info.namespace, ctx.target.buf, ctx.query.namesapce)
	vim.print(sign_text)
end

--- generate function signature text
---@param ctx BufferContext
function M.gen_func_text(ctx)
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

	return declaration
end
return M
