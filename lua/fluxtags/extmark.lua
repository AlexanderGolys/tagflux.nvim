---@class FluxtagsExtmark
---@field bufnr integer
---@field ns integer
---@field lnum integer
---@field col integer
---@field opts vim.api.keyset.set_extmark
---@field api table
local Extmark = {}
Extmark.__index = Extmark

---@param value any
---@param name string
local function required(value, name)
  assert(value ~= nil, ("fluxtags.extmark: missing required field '%s'"):format(name))
end

---@param bufnr integer
---@param ns? integer
---@param lnum integer
---@param col integer
---@param opts? vim.api.keyset.set_extmark
---@param api? table
---@return FluxtagsExtmark
function Extmark.new(bufnr, ns, lnum, col, opts, api)
  required(bufnr, "bufnr")
  required(lnum, "lnum")
  required(col, "col")

  return setmetatable({
    bufnr = bufnr,
    ns = ns or 0,
    lnum = lnum,
    col = col,
    opts = opts or {},
    api = api or vim.api,
  }, Extmark)
end

---@return boolean ok
---@return integer|string result
function Extmark:set()
  return pcall(self.api.nvim_buf_set_extmark, self.bufnr, self.ns, self.lnum, self.col, self.opts)
end

---@param bufnr integer
---@param ns? integer
---@param lnum integer
---@param col integer
---@param opts? vim.api.keyset.set_extmark
---@param api? table
---@return boolean ok
---@return integer|string result
function Extmark.place(bufnr, ns, lnum, col, opts, api)
  return Extmark.new(bufnr, ns, lnum, col, opts, api):set()
end

return Extmark
