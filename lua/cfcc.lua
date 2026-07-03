local M = {}
local api = vim.api
local lsp = require("cfcc.lsp")
local util = require("cfcc.util")

--- Execute code_action
---@param index integer? which action want to do
---@param bool boolean
function M.code_action(index, bool)
	local ok, ctx = pcall(util.current)
	if not ok then
		---@diagnostic disable-next-line: param-type-mismatch
		vim.notify(ctx)
		return
	end
	bool = bool or false
	if not index then
		vim.ui.select({
			"generate declarator/definition on header/source",
			"copy function text",
			"sync function declarator/definition",
		}, { prompt = "select a code action" }, function(_, idx)
			if idx == 1 then
				M.gen_func(ctx)
			elseif idx == 2 then
				M.copy_func(ctx, bool)
			elseif idx == 3 then
				M.sync_func(ctx)
			end
		end)
	else
		if index == 1 then
			M.gen_func(ctx)
		elseif index == 2 then
			M.copy_func(ctx, bool)
		elseif index == 3 then
			M.sync_func(ctx)
		end
	end
end

--- Generate function on target file
---@param ctx RequestContext
function M.gen_func(ctx)
	--TODO: should use coroutine rebuild
	lsp.get_target(ctx, M.get_target_callback)
end

--- Use clangd get target file callback,and do something
--- @param ctx RequestContext
--- @param uri string
function M.get_target_callback(ctx, uri)
	local origin = ctx.origin
	local target = ctx.target
	local path = vim.uri_to_fname(uri)
	if not vim.fn.filewritable(path) then
		if vim.fn.confirm(path .. "not exist,whether create it", "&yes\n&no") == 1 then
			local dir = vim.fn.fnamemodify(path, ":h")
			vim.fn.mkdir(dir, "p")
			vim.fn.writefile({}, path)
		else
			return
		end
	end
	target.buf = vim.fn.bufadd(path)
	vim.fn.bufload(target.buf)

	-- should care about change that from other software change
	-- vim.api.nvim_buf_call(target.buf, function()
	-- 	vim.cmd("checktime")
	-- end)

	local is_header = lsp.is_header(api.nvim_buf_get_name(origin.buf))
	local is_declarator = util.is_declarator(origin.info)
	ctx.cache = lsp.simple_analysis(is_header and origin.buf or target.buf, ctx.query.class, ctx.query.namespace)

	if is_header then
		if is_declarator then
			if lsp.have_definition(ctx) then
				vim.notify("has definition on source")
			else
				local row, col = lsp.gen_definition_on_source(ctx)
				api.nvim_set_current_buf(target.buf)
				api.nvim_win_set_cursor(target.buf, { row, col })
			end
		else
			-- clangd have support move definition to source
			vim.notify("clangd support mvoe definition to source")
			return
		end
	else
		if is_declarator then
			--- do nothing
			--- should move declarator to header?
			--- lsp.gen_declarator_on_header()
			--- lsp.gen_definition_on_source()
		else
			if lsp.have_definition(ctx) then
				vim.notify("has declatator on header")
			else
				local row, col = lsp.gen_declarator_on_header(ctx)
				api.nvim_set_current_buf(target.buf)
				api.nvim_win_set_cursor(target.buf, { row, col })
			end
		end
	end
end

--- Copu func text
---@param ctx RequestContext
---@param bool boolean
function M.copy_func(ctx, bool)
	bool = bool or false
	local text
	if bool then
		if util.is_declarator(ctx.origin.info) then
			text = lsp.gen_def_from_decl(ctx.origin)
		else
			text = lsp.gen_decl_from_def(ctx.origin)
		end
	else
		text = vim.treesitter.get_node_text(ctx.origin.info.full, ctx.origin.buf)
	end

	vim.fn.setreg('"', text)
	vim.notify(text)
end

--- TODO: impl sync func and select mode
---@param ctx RequestContext
function M.sync_func(ctx)
	vim.notify("waiting development")
end

return M
