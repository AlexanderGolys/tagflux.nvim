--- @brief [[
---     hl — inline highlight tags.
---
---     Syntax: `&&&<HlGroup>&&&<text>&&&`
---     All three `&&&` delimiters and the group name are fully concealed so
---     only the styled text is visible. The highlight group is taken verbatim
---     from the tag, so any valid Neovim group name works (Error, WarningMsg,
---     @keyword, DiagnosticHint, etc.).
---
---     No jump target; Ctrl-] is a no-op on hl tags.
---     Nothing is saved to a tagfile.
--- @brief ]]

-- @@@fluxtags.hl
-- ###tag-kind

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")
local kind_common = require("tagkinds.common")

local M = {}

--- Register the `hl` tag kind with fluxtags.
---
--- @param fluxtags table The main fluxtags module table
function M.register(fluxtags)
    local cfg, opts = kind_common.resolve_kind_config(
        fluxtags,
        "hl",
        {
            name = "hl",
            pattern = "&&&([%w_@-]+)&&&(.-)&&&",
            open = "&&&",
            mid = "&&&",
            close = "&&&",
            conceal_open = "",
            conceal_mid = "",
            conceal_close = "",
            hl_group = "",
        },
        prefix_util.default_comment_prefix_patterns
    )
    local kind_name = opts.name
    local pattern = opts.pattern
    local match_pattern = cfg.match_pattern or pattern
    local open = opts.open
    local mid = opts.mid
    local close = opts.close
    local prefix_patterns = opts.comment_prefix_patterns
    -- Conceal characters default to empty string = fully hidden (not just replaced).
    local conceal_open = opts.conceal_open
    local conceal_mid = opts.conceal_mid
    local conceal_close = opts.conceal_close

    local kind = tag_kind.new({
        name            = kind_name,
        pattern         = pattern,
        hl_group        = opts.hl_group,
        priority        = opts.priority,
        save_to_tagfile = false,

        extract_name = function(match) return match end,

        on_jump = function(name, ctx) return false end,
    })

    --- Custom extmark logic: the group name is embedded in the tag itself, so
    --- we cannot use the generic apply_extmarks path (which uses a fixed hl_group).
    --- Each segment is placed individually to fully hide the syntax and apply the
    --- correct group only to the visible text.
    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        local priority = self.priority or 1100
        for match_start, group, text in line:gmatch("()" .. match_pattern) do
            local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, prefix_patterns)
            local col0       = prefix_start - 1
            local open_len   = #prefix_text + #open
            local prefix_len = open_len + #group + #mid
            local text_start = col0 + prefix_len
            local text_end   = text_start + #text
            local close_end  = text_end + #close
            if not (is_disabled and is_disabled(lnum, col0)) then
                -- Hide `&&&`
                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
                    end_col  = col0 + open_len,
                    conceal  = conceal_open,
                    priority = priority,
                })
                -- Hide the group name
                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + open_len, {
                    end_col  = col0 + open_len + #group,
                    conceal  = "",
                    priority = priority,
                })
                -- Hide `&&&` between group name and text
                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + open_len + #group, {
                    end_col  = col0 + prefix_len,
                    conceal  = conceal_mid,
                    priority = priority,
                })
                -- Apply the user-specified highlight to the visible text
                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, text_start, {
                    end_col  = text_end,
                    hl_group = group,
                    priority = priority,
                })
                -- Hide trailing `&&&`
                vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, text_end, {
                    end_col  = close_end,
                    conceal  = conceal_close,
                    priority = priority,
                })
            end
        end
    end

    fluxtags.register_kind(kind)
end

return M
