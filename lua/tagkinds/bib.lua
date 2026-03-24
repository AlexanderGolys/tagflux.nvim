--- @brief [[
--- bib — external link tags.
--- @brief ]]

-- @@@fluxtags.bib
-- @##tagkind

local prefixed = require("fluxtags.prefixed_kind")

local M = {}

--- Register the `bib` link kind.
---
--- Supports URLs, file paths, and Vim help topics. Jumping opens the target using
--- `vim.ui.open` or `:help`.
---
---@param fluxtags table
---@return nil
function M.register(fluxtags)
    local binder = prefixed.binder(fluxtags, "bib", {
        name = "bib",
        pattern = " ///([%.%-/:%w]+)",
        hl_group = "FluxTagBib",
        open = " ///",
        conceal_open = "/",
    })
    local opts = binder.opts

    local kind = binder:new_kind({
        name = opts.name,
        pattern = opts.pattern,
        hl_group = opts.hl_group,
        save_to_tagfile = false,
        conceal_pattern = function(target)
            return {
                { offset = 0, length = #opts.open, char = opts.conceal_open },
                { offset = #opts.open, length = #target, hl_group = opts.hl_group },
            }
        end,
        on_jump = function(target)
            if target:match("^https?://") then
                vim.ui.open(target)
                return true
            end
            local expanded = vim.fn.expand(target)
            if vim.fn.filereadable(expanded) == 1 then
                vim.ui.open(expanded) 
                return true
            end
            if pcall(vim.cmd, "help " .. target) then return true end
            vim.notify("Cannot open: " .. target, vim.log.levels.WARN)
            return true
        end,
    })

    binder:attach_find_at_cursor(kind)
    binder:attach_prefixed_extmarks(kind, {
        open = opts.open,
        conceal_open = opts.conceal_open,
    })

    fluxtags.register_kind(kind)
end

return M
