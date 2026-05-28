local M = {}
local get_node_text = vim.treesitter.get_node_text

---comment
---@param bufnr any
---@param node TSNode
function M.debug_decl(bufnr, node)
	vim.print("declarator")
	vim.print(get_node_text(node, bufnr))
	vim.print("namde_children")
	local namde_children = node:named_children()
	-- for _, child in ipairs(namde_children) do
	-- 	vim.print(get_node_text(child, bufnr))
	-- end
	for i = 1, #namde_children do
		vim.print(get_node_text(namde_children[i], bufnr))
	end
end

---comment
---@param array TSNode[]
function M.print_array(bufnr, array)
	for i = 1, #array do
		vim.print(get_node_text(array[i], bufnr))
	end
end
---comment
---@param ctx BufferContext
function M.debug_ctx(ctx)
	M.print_array(ctx.buf, ctx.info.namespace)
	M.print_array(ctx.buf, ctx.info.class)
	print(get_node_text(ctx.info.name, ctx.buf))
end
return M
