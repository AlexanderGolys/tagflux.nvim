--- @brief [[
---     ref — references to mark tags.
---
---     Two syntaxes are supported:
---       Block form:   `-- /@@<name>` (conceals delimiters to `/@`)
---       Inline form:  `@<base>.<subtag>`  (no conceal; highlights whole token)
---
---     Pressing Ctrl-] on either form resolves the base tag name against the
---     mark tagfile and jumps to the definition. Refs are not saved to a tagfile
---     themselves — they are ephemeral pointers.
--- @brief ]]

    -- @@@fluxtags.ref
    -- @##tag-kind
-- /@@fluxtags

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")
local jump_util = require("fluxtags.jump")
local kind_common = require("fluxtags.common")

local M = {}

--- Register the `ref` tag kind with fluxtags.
---
--- @param fluxtags table The main fluxtags module table
function M.register(fluxtags)
    local marks_cfg = (fluxtags.config.kinds and fluxtags.config.kinds.mark) or {}
    local cfg, opts = kind_common.resolve_kind_config(
        fluxtags,
        "ref",
        {
            name = "ref",
            pattern = "/@@([%w_.%-%+%*%/%\\:]+)",
            hl_group = "FluxTagRef",
            conceal_open = "@@",
            priority = 1100,
        },
        prefix_util.default_comment_prefix_patterns
    )
    local kind_name = opts.name
    local pattern = opts.pattern
    local hl_group = opts.hl_group
    local prefix_patterns = opts.comment_prefix_patterns

    -- Derive open delimiter from the pattern when not set explicitly,
    -- so custom patterns with different delimiters still conceal correctly.
    local open
    if cfg.open then
        open = cfg.open
    else
        open = kind_common.derive_open(pattern, "/@@")
    end
    local conceal_open = opts.conceal_open

    -- The name of the marks kind may be customised; look it up so jumps use the
    -- right tagfile even when the user has renamed it.
    local marks_kind_name = marks_cfg.name or "mark"

    local ref_kind = tag_kind.new({
        name            = kind_name,
        pattern         = pattern,
        hl_group        = hl_group,
        priority        = opts.priority,
        save_to_tagfile = false,

        is_valid = kind_common.is_valid_name,

        --- Conceal `-- /@@` to `/@`; keep the name highlighted.
        conceal_pattern = function(name)
            return {
                { offset = 0,                   length = #open,  char = conceal_open  },
                { offset = #open,               length = #name,  hl_group = hl_group  },
            }
        end,

        --- Resolve the ref name against the mark tagfile and jump.
        --- For subtags (e.g., @fluxtags.config), first try the full name,
        --- then fall back to the base name (e.g., @@@fluxtags).
        on_jump = function(name, ctx)
            local tags    = ctx.utils.load_tagfile(marks_kind_name)
            local entries, resolved = jump_util.find_entries(tags, name)
            
            if entries and entries[1] then
                return jump_util.jump_to_entry(name, resolved, entries[1], ctx)
            end
            vim.notify("Tag not found: " .. name, vim.log.levels.WARN)
            return true
        end,
    })

    --- Override find_at_cursor to also detect the inline `@base.sub` form.
    function ref_kind:find_at_cursor(line, col)
        local name, s, e = prefix_util.find_tag_at_cursor(line, col, self.pattern, prefix_patterns)
        if name then
            return name, s, e
        end

        -- Fall back to inline dotted form: @word.word (requires at least one dot).
        return prefix_util.find_match_at_cursor(
            line,
            col,
            kind_common.INLINE_SUBTAG_PATTERN
        )
    end

    --- Override apply_extmarks to handle both block and inline forms.
    function ref_kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        local priority = self.priority or 1100

        -- Block form: conceal delimiter, highlight name.
        for match_start, name in line:gmatch("()" .. self.pattern) do
            local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, prefix_patterns)
            local col0 = prefix_start - 1
            local open_len = #prefix_text + #open
            if not (is_disabled and is_disabled(lnum, col0)) then
                pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0, {
                    end_col  = col0 + open_len,
                    conceal  = conceal_open,
                    hl_group = self.hl_group,
                    priority = priority,
                })
                pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0 + open_len, {
                    end_col  = col0 + open_len + #name,
                    hl_group = self.hl_group,
                    priority = priority,
                })
            end
        end

        -- Inline form: highlight the whole `@base.sub` token without concealing.
        for match_start, ref in line:gmatch("()@([%w_.%-%+%*%/%\\:]+%.[%w_.%-%+%*%/%\\:]+)") do
            local col0 = match_start - 1
            if not (is_disabled and is_disabled(lnum, col0)) then
                pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0, {
                    end_col  = col0 + 1 + #ref,
                    hl_group = self.hl_group,
                    priority = priority,
                })
            end
        end
    end

    fluxtags.register_kind(ref_kind)
end

return M
