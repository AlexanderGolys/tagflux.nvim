local jump_util = require("fluxtags.jump")
local picker_util = require("fluxtags.picker")
local Extmark = require("fluxtags.extmark")

local M = {}

---@class MissingTagDiagnostic
---@field diags vim.Diagnostic[]
---@field bufnr integer
---@field lnum integer
---@field col integer
---@field end_col integer
---@field severity integer
---@field source string
---@field message_prefix string
---@field name string

--- Push a single diagnostic entry into a list.
---
---@param diags vim.Diagnostic[]
---@param bufnr number
---@param lnum number
---@param col number
---@param end_col number
---@param severity integer
---@param source string
---@param message string
function M.push_diag(diags, bufnr, lnum, col, end_col, severity, source, message)
  table.insert(diags, {
    bufnr = bufnr,
    lnum = lnum,
    col = col,
    end_col = end_col,
    severity = severity,
    source = source,
    message = message,
  })
end

--- Publish diagnostics to a namespace.
---
---@param bufnr number
---@param ns number
---@param diags vim.Diagnostic[]
---@param set_diagnostics fun(bufnr:number, ns:number, diags:vim.Diagnostic[])
function M.publish_diags(bufnr, ns, diags, set_diagnostics)
  set_diagnostics(bufnr, ns, diags)
end

--- Place a temporary error extmark used by validators.
---
---@param bufnr number
---@param ns number
---@param lnum number
---@param col number
---@param end_col number
---@param priority number
function M.error_extmark(bufnr, ns, lnum, col, end_col, priority)
  Extmark.place(bufnr, ns, lnum, col, {
    end_col = end_col,
    hl_group = "FluxTagError",
    priority = priority,
  })
end

---@class FluxtagsTagEntry
---@field file string
---@field lnum integer
---@field col? integer

---@class FluxtagsTagStore: table<string, FluxtagsTagEntry[]>

---@class TagKindRuntime
---@field fluxtags table
local Runtime = {}
Runtime.__index = Runtime

---@param fluxtags table
---@return TagKindRuntime
function Runtime.new(fluxtags)
  ---@type TagKindRuntime
  local self = setmetatable({
    fluxtags = fluxtags,
  }, Runtime)
  return self
end

---@param kind_name string
---@return FluxtagsTagStore
function Runtime:load(kind_name)
  return self.fluxtags.utils.load_tagfile(kind_name)
end

---@param message string
function Runtime:warn(message)
  vim.notify(message, vim.log.levels.WARN)
end

---@param kind_name string
---@param name string
---@param ctx table
---@param not_found_prefix string
---@return boolean
function Runtime:jump_to_first(kind_name, name, ctx, not_found_prefix)
  local tags = ctx.utils.load_tagfile(kind_name)
  local entries, resolved = jump_util.find_entries(tags, name)
  if entries and entries[1] then
    return jump_util.jump_to_entry(name, resolved, entries[1], ctx)
  end
  self:warn(("%s%s"):format(not_found_prefix, name))
  return true
end

---@param kind_name string
---@param name string
---@param ctx table
---@param missing_message string
---@param title_prefix string
---@return boolean
function Runtime:pick_tag_locations(kind_name, name, ctx, missing_message, title_prefix)
  local entries = self:load(kind_name)[name]
  if not entries or #entries == 0 then
    self:warn(missing_message .. name)
    return true
  end
  picker_util.pick_locations(entries, title_prefix .. name, ctx)
  return true
end

---@param params MissingTagDiagnostic
function Runtime:push_missing_tag_diagnostic(params)
  M.push_diag(
    params.diags,
    params.bufnr,
    params.lnum,
    params.col,
    params.end_col,
    params.severity,
    params.source,
    ("%s%s"):format(params.message_prefix, params.name)
  )
end

---@param fluxtags table
---@return TagKindRuntime
function M.new_runtime(fluxtags)
  return Runtime.new(fluxtags)
end

M.Runtime = Runtime

return M
