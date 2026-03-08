local M = {}
local Extmark = require("fluxtags.extmark")

---@class FluxtagsDiagnostic
---@field bufnr number
---@field lnum number
---@field col number
---@field end_col number
---@field severity integer
---@field source string
---@field message string

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
function M.push(diags, bufnr, lnum, col, end_col, severity, source, message)
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
function M.publish(bufnr, ns, diags, set_diagnostics)
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

return M
