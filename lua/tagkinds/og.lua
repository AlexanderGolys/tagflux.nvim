--- @brief [[
--- og — hashtag tags.
--- @brief ]]

local prefixed = require("tagkinds.prefixed_kind")
local picker_util = require("fluxtags.picker")
local prefix_util = require("fluxtags.prefix")
local kind_common = require("fluxtags.common")

local M = {}

---@param fluxtags table
function M.register(fluxtags)
    local binder = prefixed.binder(fluxtags, "og", {
        name = "og",
        pattern = "@##([%w_%.%-%+%*/%\\:]+)",
        hl_group = "FluxTagOg",
        open = "@##",
        conceal_open = "#",
    })
    local opts = binder.opts

    local kind = binder:new_kind({
        name = opts.name,
        pattern = opts.pattern,
        hl_group = opts.hl_group,
        priority = opts.priority,
        save_to_tagfile = true,
        is_valid = kind_common.is_valid_name,
        conceal_pattern = function(name)
            return {
                { offset = 0, length = #opts.open, char = opts.conceal_open },
                { offset = #opts.open, length = #name, hl_group = opts.hl_group },
            }
        end,
        on_jump = function(name, ctx)
            local tags = ctx.utils.load_tagfile(ctx.kind_name)
            local entries = tags[name]
            if not entries or #entries == 0 then
                vim.notify("No tags found: #" .. name, vim.log.levels.WARN)
                return true
            end
            picker_util.pick_locations(entries, "#" .. name, ctx)
            return true
        end,
    })

    binder:attach_find_at_cursor(kind)
    binder:attach_prefixed_extmarks(kind, {
        open = opts.open,
        conceal_open = opts.conceal_open,
    })

    function kind:collect_tags(filepath, lines, is_disabled)
        local tags = {}
        for lnum, line in ipairs(lines) do
            for match_start, name in line:gmatch("()" .. opts.pattern) do
                local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, opts.comment_prefix_patterns)
                local col0 = prefix_start - 1
                if not (is_disabled and is_disabled(lnum - 1, col0)) then
                    table.insert(tags, {
                        name = name,
                        file = filepath,
                        lnum = lnum,
                        col = col0 + #prefix_text + #opts.open + 1,
                    })
                end
            end
        end
        return tags
    end

    fluxtags.register_kind(kind)
end

return M
