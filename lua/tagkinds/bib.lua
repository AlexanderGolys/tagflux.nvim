local tag_kind = require("tag_kind")

local M = {}

function M.register(fluxtags)
    local cfg = (fluxtags.config.kinds and fluxtags.config.kinds.bib) or {}
    local kind_name = cfg.name or "bib"
    local pattern = cfg.pattern or "/(%S+)"
    local hl_group = cfg.hl_group or "FluxTagBib"

    local kind = tag_kind.new({
        name = kind_name,
        pattern = pattern,
        hl_group = hl_group,
        priority = cfg.priority,
        save_to_tagfile = false,
        
        on_jump = function(ref, ctx)
            if ref:match("^https?://") or ref:match("^www%.") then
                vim.ui.open(ref)
                return true
            end
            
            local path = vim.fn.expand(ref)
            if vim.fn.filereadable(path) == 1 then
                vim.ui.open(path)
                return true
            end
            
            local ok = pcall(vim.cmd, "help " .. ref)
            if ok then return true end

            vim.notify("Cannot open: " .. ref, vim.log.levels.WARN)
            return true
        end,
    })
    
    fluxtags.register_kind(kind)
end

return M
