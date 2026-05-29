---@class FunctionInfo
---@field func TSNode function declarator
---@field name TSNode function name
---@field class TSNode[] class name
---@field namespace TSNode[] namespace name
---@field is_declarator boolean whether
---@field full TSNode all function body (declaration)

---@class BufferContext
---@field buf integer
---@field info FunctionInfo

---@class QueryContext
---@field func vim.treesitter.Query
---@field namespace vim.treesitter.Query
---@field class vim.treesitter.Query

---@class RequestContext
---@field origin BufferContext
---@field target BufferContext
---@field query QueryContext

---@class MatchFuncInfo
---@field name boolean whether function name is equal
---@field params boolean whether function params are equal

---@class FunctionNameInfo
---@field scope TSNode[]
---@field name TSNode

---@class FunctionPartInfo
---@field noptr TSNode
---@field name FunctionNameInfo
---@field cv TSNode[]
---@field ref TSNode?
---@field noexcept TSNode?
---@field throw TSNode?
---@field trailing TSNode?

---@class DeleteParamHelp which nodes that between last and end should be delete (just for lsp help)
---@field last TSNode  last keep node
---@field final TSNode end node
