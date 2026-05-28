local M = {}
local lsp = require("cfcc.lsp")
local ast = require("cfcc.ast")
local util = require("cfcc.util")
local api = vim.api

function M.code_action()
	local ok, ctx = pcall(util.current)
	if not ok then
		---@diagnostic disable-next-line: param-type-mismatch
		vim.notify(ctx)
		return
	end

	-- generate declatator/definition on header/soruce
	-- copy function text to paste
	-- change function declatator/definition to make params same
	vim.ui.select({
		"generate declarator/definition on header/source",
		"copy function text",
		"sync function declarator/definition",
	}, { prompt = "select a code action" }, function(_, idx)
		if idx == 1 then
			M.gen_func(ctx)
		elseif idx == 2 then
			M.copy_func(ctx)
		elseif idx == 3 then
			M.sync_func(ctx)
		end
	end)
end

--- generate function on target file
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
		if vim.fn.confirm(path .. "not exist,whether create it", "&yes\n&no") then
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

	if is_header then
		if is_declarator then
			if lsp.have_definition(ctx) then
				vim.notify("has definition on source")
			else
				lsp.gen_definition_on_source(ctx)
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
		else
			if lsp.have_definition(ctx) then
				vim.notify("has declatator on header")
			else
				lsp.gen_declarator_on_header(ctx)
			end
		end
	end
end

---@param ctx RequestContext
function M.copy_func(ctx)
	local text = lsp.gen_func_text(ctx.origin)
	vim.fn.setreg('"', text)
end
---@param ctx RequestContext
function M.sync_func(ctx) end

return M
