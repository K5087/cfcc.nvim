---@class FunctionInfo
---@field func TSNode function declarator
---@field name TSNode function name
---@field class TSNode[] class name   outer ... inner
---@field namespace TSNode[] namespace name  outer ... inner
---@field scope TSNode[] temp cache function name scope
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
---@field cache {namespace:TSNode[],class:TSNode[]}
