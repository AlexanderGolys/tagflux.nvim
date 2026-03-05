--- @brief [[
--- bib — external link tags.
--- @brief ]]

local prefixed = require("tagkinds.prefixed")

local M = {}

---@param fluxtags table
function M.register(fluxtags)
    local _, opts = prefixed.resolve(fluxtags, "bib", {
        name = "bib",
        pattern = "///([%.%-/:%w]+)",
        hl_group = "FluxTagBib",
        open = "///",
        conceal_open = "/",
    })

    local kind = prefixed.new_kind({
        name = opts.name,
        pattern = opts.pattern,
        hl_group = opts.hl_group,
        priority = opts.priority,
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

    prefixed.attach_find_at_cursor(kind, opts.pattern, opts.comment_prefix_patterns)
    prefixed.attach_prefixed_extmarks(kind, opts.pattern, opts.comment_prefix_patterns, {
        open = opts.open,
        conceal_open = opts.conceal_open,
    })

    fluxtags.register_kind(kind)
end

return M
