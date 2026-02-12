local tag_kind = require("tag_kind")

local M = {}

function M.register(fluxtags)
    local cfg = (fluxtags.config.kinds and fluxtags.config.kinds.hl) or {}
    local kind_name = cfg.name or "hl"
    local pattern = cfg.pattern or "~([%w_]+):(.-)~"
    local match_pattern = cfg.match_pattern or pattern

    local kind = tag_kind.new({
        name = kind_name,
        pattern = pattern,
        hl_group = cfg.hl_group or "",
        priority = cfg.priority,
        save_to_tagfile = false,
        
        extract_name = function(match)
            local group, text = match:match("^([%w_]+):(.+)$")
            return group .. ":" .. text
        end,
        
        on_jump = function(name, ctx)
            return false
        end,
    })
    
    -- Override apply_extmarks for custom highlighting logic
    function kind:apply_extmarks(bufnr, lnum, line, ns)
        local priority = self.priority or 1100
        for start_col, group, text in line:gmatch("()" .. match_pattern) do
            local col0 = start_col - 1
            local full_len = 2 + #group + 1 + #text

            vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
                end_col = col0 + 1 + #group + 1,
                conceal = "",
            })
            vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + 1 + #group + 1, {
                end_col = col0 + full_len - 1,
                hl_group = group,
                priority = priority,
            })
            vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + full_len - 1, {
                end_col = col0 + full_len,
                conceal = "",
            })
        end
    end
    
    fluxtags.register_kind(kind)
end

return M
