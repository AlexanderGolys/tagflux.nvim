--- @brief [[
---     refog — references to og hashtag tags.
---
---     Syntax: `#|#||<name>||`
---     Unlike `og` tags, refog entries are not persisted to a tagfile and do
---     not create additional hashtag occurrences. They only resolve and jump to
---     existing saved `og` entries.
--- @brief ]]

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")
local picker_util = require("fluxtags.picker")
local kind_common = require("tagkinds.common")

local M = {}

--- Register the `refog` tag kind with fluxtags.
---
--- @param fluxtags table The main fluxtags module table
function M.register(fluxtags)
    local og_cfg = (fluxtags.config.kinds and fluxtags.config.kinds.og) or {}
    local _, opts = kind_common.resolve_kind_config(
        fluxtags,
        "refog",
        {
            name = "refog",
            pattern = "#|#||([%w_.%-%+%*%/%\\:]+)||",
            hl_group = "FluxTagRef",
            open = "#|#||",
            close = "||",
            conceal_open = "#",
            conceal_close = "",
        },
        prefix_util.default_comment_prefix_patterns
    )
    local kind_name = opts.name
    local pattern = opts.pattern
    local hl_group = opts.hl_group
    local open = opts.open
    local close = opts.close
    local conceal_open = opts.conceal_open
    local conceal_close = opts.conceal_close
    local prefix_patterns = opts.comment_prefix_patterns
    local og_kind_name  = og_cfg.name or "og"

    local kind = tag_kind.new({
        name            = kind_name,
        pattern         = pattern,
        hl_group        = hl_group,
        priority        = opts.priority,
        save_to_tagfile = false,

        is_valid = kind_common.is_valid_name,

        conceal_pattern = function(name)
            return {
                { offset = 0,             length = #open,  char = conceal_open },
                { offset = #open,         length = #name,  hl_group = hl_group },
                { offset = #open + #name, length = #close, char = conceal_close },
            }
        end,

        on_jump = function(name, ctx)
            local tags = ctx.utils.load_tagfile(og_kind_name)
            local entries = tags[name]
            if not entries or #entries == 0 then
                vim.notify("No og tags found: #" .. name, vim.log.levels.WARN)
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
            close = close,
            conceal_open = conceal_open,
            conceal_close = conceal_close,
            hl_group = self.hl_group,
            priority = self.priority,
        }, is_disabled)
    end

    fluxtags.register_kind(kind)
end

return M
