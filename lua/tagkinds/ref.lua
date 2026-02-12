local tag_kind = require("tag_kind")

local M = {}

local function get_base_tag(ref)
    return ref:match("^([^.]+)")
end

function M.register(fluxtags)
    local cfg = (fluxtags.config.kinds and fluxtags.config.kinds.ref) or {}
    local marks_cfg = (fluxtags.config.kinds and fluxtags.config.kinds.marks) or {}
    local kind_name = cfg.name or "ref"
    local hl_group = cfg.hl_group or "FluxTagRef"
    local pattern = cfg.pattern or "|||(%S+)|||"
    local open = cfg.open
    local close = cfg.close
    if not open or not close then
        local inferred_open = pattern:match("^(.-)%(%S%+%)")
        local inferred_close = pattern:match("%(%S%+%)(.+)$")
        open = open or inferred_open or "|||"
        close = close or inferred_close or "|||"
    end
    local conceal_open = cfg.conceal_open or open:sub(1, 1)
    local conceal_close = cfg.conceal_close or close:sub(1, 1)
    local marks_kind_name = marks_cfg.name or "marks"
    local ref_kind = tag_kind.new({
        name = kind_name,
        pattern = pattern,
        hl_group = hl_group,
        priority = 1100,
        save_to_tagfile = false,
        
        conceal_pattern = function(name)
            return {
                { offset = 0, length = #open, char = conceal_open },
                { offset = #open, length = #name, hl_group = hl_group },
                { offset = #open + #name, length = #close, char = conceal_close },
            }
        end,
        
        on_jump = function(name, ctx)
            local tags = ctx.utils.load_tagfile(marks_kind_name)
            local entries = tags[name]
            if entries and entries[1] then
                local t = entries[1]
                vim.cmd("edit " .. vim.fn.fnameescape(t.file))
                vim.fn.cursor(t.lnum, 1)
                return true
            end
            vim.notify("Tag not found: " .. name, vim.log.levels.WARN)
            return true
        end,
    })
    
    -- Override find_at_cursor to handle both patterns
    function ref_kind:find_at_cursor(line, col)
        local start_pos = 1
        while true do
            local s, e, name = line:find(self.pattern, start_pos)
            if not s then break end
            if col >= s and col <= e then return name, s, e end
            start_pos = e + 1
        end
        
        start_pos = 1
        while true do
            local s, e, ref = line:find("@([%w_.]+%.[%w_.]+)", start_pos)
            if not s then return nil end
            if col >= s and col <= e then return get_base_tag(ref), s, e end
            start_pos = e + 1
        end
    end
    
    -- Override apply_extmarks to handle both patterns
    function ref_kind:apply_extmarks(bufnr, lnum, line, ns)
        local priority = self.priority or 1100
        for start_col, name in line:gmatch("()" .. self.pattern) do
            local col0 = start_col - 1
            vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, { 
                end_col = col0 + #open, 
                conceal = conceal_open,
                priority = priority,
            })
            vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + #open, {
                end_col = col0 + #open + #name,
                hl_group = self.hl_group,
                priority = priority,
            })
            vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + #open + #name, { 
                end_col = col0 + #open + #name + #close, 
                conceal = conceal_close,
                priority = priority,
            })
        end
        
        for start_col, ref in line:gmatch("()@([%w_.]+%.[%w_.]+)") do
            local col0 = start_col - 1
            vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
                end_col = col0 + 1 + #ref,
                hl_group = self.hl_group,
                priority = priority,
            })
        end
    end
    
    fluxtags.register_kind(ref_kind)
end

return M
