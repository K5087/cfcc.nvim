local M = {}
local lsp = require("cfcc.lsp")
local ast = require("cfcc.ast")

function M.check_func_sign()
	local bufnr = vim.api.nvim_get_current_buf()
	local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })
	if #clients < 1 then
		vim.notify("cannot find clangd client")
		return
	end

	local clangd_client = clients[1]

	local node = vim.treesitter.get_node({ bufnr = bufnr })
	if not node then
		vim.notify("current cursor have no treesitter node")
		return
	end

	local info = ast.GetFunctionSign(node)
	if not info then
		vim.notify("cannot find function signature")
		return
	end

	-- local text = ast.node_text(info.function_declarator, bufnr)
	lsp.edit_target(bufnr, clangd_client, M.handle_requrest)
end

--- handle request
---@param request RequestInfo
function M.handle_requrest(request)
	local info = request.info
	local from_header = request.origin == request.header
	local func_nodes, full_match_id =
		ast.search_function(request.target, { bufnr = request.origin, node = request.info.func })
	local messages = {}
	for _, node in ipairs(func_nodes) do
		table.insert(messages, ast.node_text(request.target, node))
	end
	-- vim.print(messages)

	if full_match_id ~= 0 then
		vim.notify("there has declatator and definition in header/source file")
		return
	end

	vim.ui.select(
		{ "generate declarator in header", "generate definition in source" },
		{ prompt = "select a action" },
		function(item, idx)
			if idx == 1 then
				if info.is_declarator == true and from_header then
					vim.notify("there has a function declatator in header")
					return
				end

				lsp.generate_declarator_on_header(request)
			elseif idx == 2 then
				if info.is_declarator == false and not from_header then
					vim.notify("there has a function definition in source")
					return
				end
				lsp.generate_definition_on_source(request)
			end
		end
	)
end

return M
