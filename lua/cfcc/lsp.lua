local M = {}
local ast = require("cfcc.ast")

---@class RequestInfo
---@field header integer cpp header file buffer id
---@field source integer cpp source file buffer id
---@field info FunctionInfo function ast info
---@field origin integer which bufnr launch request
---@field target integer which bufnr should change

---get change param
---@param origin_bufnr integer which bufnr requrest
---@param uri string target file path
---@return RequestInfo?
local function generate_request_param(origin_bufnr, uri)
	local is_header = M.is_header(vim.api.nvim_buf_get_name(origin_bufnr))
	local param = {
		origin = origin_bufnr,
	}
	if is_header then
		param.header = origin_bufnr
	else
		param.source = origin_bufnr
	end

	local path = vim.uri_to_fname(uri)
	if not vim.fn.filewritable(path) then
		if vim.fn.confirm(path .. "not exist,whether create it", "&yes\n&no") then
			local dir = vim.fn.fnamemodify(path, ":h")
			vim.fn.mkdir(dir, "p")
			vim.fn.writefile({}, path)
		else
			return param
		end
	end
	local target_bufnr = vim.fn.bufadd(path)
	if target_bufnr < 0 then
		vim.notify("file" .. "not exist")
		return param
	end
	vim.fn.bufload(target_bufnr)

	if not target_bufnr then
		return param
	end
	param.target = target_bufnr
	if is_header then
		param.source = target_bufnr
	else
		param.header = target_bufnr
	end

	local node = vim.treesitter.get_node({ bufnr = origin_bufnr })

	if not node then
		vim.notify("cannot find ast node")
		return param
	end
	local info = ast.GetFunctionSign(node)
	if not info then
		vim.notify("cannot find function signature")
		return param
	end
	param.info = info
	return param
end

---check file path whether cpp header
---@param path string file path
---@return boolean
function M.is_header(path)
	local ext = vim.fn.fnamemodify(path, ":e")
	return ext == "h" or ext == "hxx"
end

---write function signature to target file
---@param bufnr integer
---@param client vim.lsp.Client
---@param func function(RequestInfo)
function M.edit_target(bufnr, client, func)
	local method_name = "textDocument/switchSourceHeader"
	---@diagnostic disable-next-line:param-type-mismatch
	if not client or not client:supports_method(method_name) then
		return vim.notify(
			("method %s is not supported by any servers active on the current buffer"):format(method_name)
		)
	end
	local params = vim.lsp.util.make_text_document_params(bufnr)
	---@diagnostic disable-next-line:param-type-mismatch
	client:request(method_name, params, function(err, result)
		if err then
			error(tostring(err))
		end
		if not result then
			vim.notify("corresponding file cannot be determined")
			return
		end

		local param = generate_request_param(bufnr, result)

		func(param)
	end, bufnr)
end

---generate function signature text
---@param info FunctionInfo
---@return string
local function Generate_Function_Text(bufnr, info)
	local declaration = ast.node_text(bufnr, info.full)
	local del_ranges = ast.get_del_optparam_ranges2(bufnr, info.full, info.func)

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

---comment
---@param info RequestInfo
function M.generate_declarator_on_header(info)
	local sign_text = Generate_Function_Text(info.origin, info.info)
	vim.print(sign_text)
end
---comment
---@param info RequestInfo
function M.generate_definition_on_source(info)
	local sign_text = Generate_Function_Text(info.origin, info.info)
	vim.print(sign_text)
end

return M
