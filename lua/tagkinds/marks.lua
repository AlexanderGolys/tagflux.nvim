-- @@@fluxtags.mark

local tag_kind = require("tag_kind")

local M = {}

function M.register(fluxtags)
    local cfg = (fluxtags.config.kinds and fluxtags.config.kinds.marks) or {}
    local kind_name = cfg.name or "marks"
    local pattern = cfg.pattern or "@@@(%S+)"
    local hl_group = cfg.hl_group or "FluxTagMarks"
    local open = cfg.open or "@@@"
    local conceal_open = cfg.conceal_open or open:sub(1, 1)

    local kind = tag_kind.new({
        name = kind_name,
        pattern = pattern,
        hl_group = hl_group,
        priority = cfg.priority,
        save_to_tagfile = true,
        
        conceal_pattern = function(name)
            return {
                { offset = 0, length = #open, char = conceal_open },
                { offset = #open, length = #name, hl_group = hl_group },
            }
        end,
        
        on_jump = function(name, ctx)
            local tags = ctx.utils.load_tagfile(ctx.kind_name)
            if tags[name] and tags[name][1] then
                local t = tags[name][1]
                vim.cmd("edit " .. vim.fn.fnameescape(t.file))
                vim.fn.cursor(t.lnum, 1)
                vim.fn.search("@@@" .. name, "c", t.lnum)
                return true
            end
            return false
        end,
    })
    
    fluxtags.register_kind(kind)
end

return M
