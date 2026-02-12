local tag_kind = require("tag_kind")

local M = {}

local handlers = {
    ft = function(value, bufnr)
        vim.bo[bufnr].filetype = value
    end,
    conceallevel = function(value, bufnr)
        vim.wo[bufnr].conceallevel = tonumber(value) or 0
    end,
    fluxtags = function(value, bufnr)
        if value == "off" then
            vim.b[bufnr].fluxtags_disabled = true
        end
    end,
    modeline = function(value, bufnr)
        vim.api.nvim_buf_call(bufnr, function()
            pcall(vim.cmd, value)
        end)
    end,
}

function M.register(fluxtags)
    local cfg = (fluxtags.config.kinds and fluxtags.config.kinds.cfg) or {}
    local kind_name = cfg.name or "cfg"
    local pattern = cfg.pattern or "%$([%w_]+):([^\n%s]+)"

    local kind = tag_kind.new({
        name = kind_name,
        pattern = pattern,
        hl_group = cfg.hl_group or "FluxTagCfg",
        priority = cfg.priority,
        save_to_tagfile = false,
        
        extract_name = function(match)
            local key, value = match:match("^([%w_]+):(.+)$")
            return key .. ":" .. value
        end,
        
        on_jump = function(name, ctx)
            return false
        end,
        
        on_enter = function(bufnr, lines)
            for _, line in ipairs(lines) do
                for key, value in line:gmatch(pattern) do
                    if handlers[key] then
                        handlers[key](value, bufnr)
                    end
                end
            end
        end,
    })
    
    -- Override apply_extmarks for two-capture pattern
    function kind:apply_extmarks(bufnr, lnum, line, ns)
        local priority = self.priority or 1100
        for start_col, key, value in line:gmatch("()" .. pattern) do
            local col0 = start_col - 1
            vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
                end_col = col0 + 1 + #key + 1 + #value,
                hl_group = self.hl_group,
                priority = priority,
            })
        end
    end
    
    fluxtags.register_kind(kind)
end

function M.register_handler(key, fn)
    handlers[key] = fn
end

return M
