--- @brief [[
---     og — hashtag / topic-grouping tags.
---
---     Syntax: `@##<name>`
---     Unlike marks, the same hashtag name can appear in many files. Pressing
---     Ctrl-] opens a picker listing every occurrence so the user can navigate
---     between all usages of the topic. Falls back to vim.ui.select when
---     Telescope is not available.
---
---     Tags are saved to a tagfile and listed via `:FTagsList og`.
---     The `@##` prefix is concealed to `#` when conceallevel >= 1.
--- @brief ]]

-- @@@fluxtags.og
-- @##tag-kind

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")
local picker_util = require("fluxtags.picker")
local kind_common = require("fluxtags.common")

local M = {}

--- Register the `og` tag kind with fluxtags.
---
--- @param fluxtags table The main fluxtags module table
function M.register(fluxtags)
    local _, opts = kind_common.resolve_kind_config(
        fluxtags,
        "og",
        {
            name = "og",
            pattern = "@##([%w_.%-%+%*%/%\\:]+)",
            hl_group = "FluxTagOg",
            open = "@##",
            conceal_open = "#",
        },
        prefix_util.default_comment_prefix_patterns
    )
    local kind_name = opts.name
    local pattern = opts.pattern
    local hl_group = opts.hl_group
    local open = opts.open
    local conceal_open = opts.conceal_open
    local prefix_patterns = opts.comment_prefix_patterns

    local kind = tag_kind.new({
        name            = kind_name,
        pattern         = pattern,
        hl_group        = hl_group,
        priority        = opts.priority,
        save_to_tagfile = true,

        is_valid = kind_common.is_valid_name,

        --- Conceal optional comment prefix + `@##` to `#`.
        conceal_pattern = function(name)
            return {
                { offset = 0,     length = #open, char = conceal_open },
                { offset = #open, length = #name, hl_group = hl_group },
            }
        end,

        --- Open a picker showing all occurrences of the hashtag.
        --- Uses Telescope when available, falls back to vim.ui.select.
        on_jump = function(name, ctx)
            local tags    = ctx.utils.load_tagfile(ctx.kind_name)
            local entries = tags[name]

            if not entries or #entries == 0 then
                vim.notify("No tags found: #" .. name, vim.log.levels.WARN)
                return true
            end

            picker_util.pick_locations(entries, "#" .. name, ctx)
            return true
        end,
    })

    function kind:find_at_cursor(line, col)
        return prefix_util.find_tag_at_cursor(line, col, self.pattern, prefix_patterns)
    end

    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        prefix_util.apply_prefixed_extmarks(bufnr, ns, lnum, line, pattern, prefix_patterns, {
            open = open,
            conceal_open = conceal_open,
            hl_group = self.hl_group,
            priority = self.priority,
        }, is_disabled)
    end

    --- Override collect_tags to record the column of each match so the picker
    --- can position the cursor precisely on the hashtag, not just the line start.
    function kind:collect_tags(filepath, lines, is_disabled)
        local tags = {}
        for lnum, line in ipairs(lines) do
            for match_start, name in line:gmatch("()" .. pattern) do
                local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, prefix_patterns)
                local col0 = prefix_start - 1
                if not (is_disabled and is_disabled(lnum - 1, col0)) then
                    table.insert(tags, {
                        name = name,
                        file = filepath,
                        lnum = lnum,
                        col  = col0 + #prefix_text + #open + 1,
                    })
                end
            end
        end
        return tags
    end

    fluxtags.register_kind(kind)
end

return M
