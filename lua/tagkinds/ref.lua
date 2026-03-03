--- @brief [[
---     ref — references to mark tags.
---
---     Two syntaxes are supported:
---       Block form:   `-- |||<name>|||`   (conceals delimiters to `|`)
---       Inline form:  `@<base>.<subtag>`  (no conceal; highlights whole token)
---
---     Pressing Ctrl-] on either form resolves the base tag name against the
---     mark tagfile and jumps to the definition. Refs are not saved to a tagfile
---     themselves — they are ephemeral pointers.
--- @brief ]]

-- @@@fluxtags.ref
-- ###tag-kind

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")

local M = {}

--- Extract the base name from a possibly-dotted ref (e.g. "config.defaults" -> "config").
--- @param ref string
--- @return string
local function base_tag_name(ref)
    return ref:match("^([^.]+)")
end

--- Register the `ref` tag kind with fluxtags.
---
--- @param fluxtags table The main fluxtags module table
function M.register(fluxtags)
    local cfg        = (fluxtags.config.kinds and fluxtags.config.kinds.ref)  or {}
    local marks_cfg  = (fluxtags.config.kinds and fluxtags.config.kinds.mark) or {}
    local kind_name  = cfg.name     or "ref"
    local hl_group   = cfg.hl_group or "FluxTagRef"
    local pattern    = cfg.pattern  or "|||([%w_.%-%+%*%/%\\:]+)|||"
    local prefix_patterns = cfg.comment_prefix_patterns or prefix_util.default_comment_prefix_patterns

    -- Derive open/close delimiters from the pattern when not set explicitly,
    -- so custom patterns with different delimiters still conceal correctly.
    local open, close
    if cfg.open and cfg.close then
        open, close = cfg.open, cfg.close
    else
        open  = pattern:match("^(.-)%(%S%+%)") or "|||"
        close = pattern:match("%(%S%+%)(.+)$") or "|||"
    end
    local conceal_open  = cfg.conceal_open  or "|"
    local conceal_close = cfg.conceal_close or "|"

    -- The name of the marks kind may be customised; look it up so jumps use the
    -- right tagfile even when the user has renamed it.
    local marks_kind_name = marks_cfg.name or "mark"

    local ref_kind = tag_kind.new({
        name            = kind_name,
        pattern         = pattern,
        hl_group        = hl_group,
        priority        = 1100,
        save_to_tagfile = false,

        is_valid = function(name)
            return name:match("^[%w_.%-%+%*%/%\\:]+$") ~= nil
        end,

        --- Conceal `-- |||` and trailing `|||`; keep the name highlighted.
        conceal_pattern = function(name)
            return {
                { offset = 0,                   length = #open,  char = conceal_open  },
                { offset = #open,               length = #name,  hl_group = hl_group  },
                { offset = #open + #name,       length = #close, char = conceal_close },
            }
        end,

        --- Resolve the ref name against the mark tagfile and jump.
        --- For subtags (e.g., @fluxtags.config), first try the full name,
        --- then fall back to the base name (e.g., @@@fluxtags).
        on_jump = function(name, ctx)
            local tags    = ctx.utils.load_tagfile(marks_kind_name)
            local entries = tags[name]
            
            -- Try the full name first, then fall back to base name for subtags
            if not entries then
                local base = base_tag_name(name)
                if base ~= name then
                    entries = tags[base]
                end
            end
            
            if entries and entries[1] then
                local entry = entries[1]
                ctx.utils.open_file(entry.file, ctx)
                local line = vim.api.nvim_buf_get_lines(0, entry.lnum - 1, entry.lnum, false)[1] or ""
                local col  = line:find(name, 1, true)
                if not col then
                    -- If the full name wasn't found in the line, try the base name
                    local base = base_tag_name(name)
                    if base ~= name then
                        col = line:find(base, 1, true)
                    end
                end
                vim.fn.cursor(entry.lnum, col or 1)
                return true
            end
            vim.notify("Tag not found: " .. name, vim.log.levels.WARN)
            return true
        end,
    })

        --- Override find_at_cursor to also detect the inline `@base.sub` form.
    function ref_kind:find_at_cursor(line, col)
        -- Check block form first.
        local search_from = 1
        while true do
            local s, e, name = line:find(self.pattern, search_from)
            if not s then break end
            local prefix_start = prefix_util.find_prefix(line, s, prefix_patterns)
            if col >= prefix_start and col <= e then return name, prefix_start, e end
            search_from = e + 1
        end

        -- Fall back to inline dotted form: @word.word (requires at least one dot).
        search_from = 1
        while true do
            local s, e, ref = line:find("@([%w_.%-%+%*%/%\\:]+%.[%w_.%-%+%*%/%\\:]+)", search_from)
            if not s then return nil end
            if col >= s and col <= e then return ref, s, e end
            search_from = e + 1
        end
    end

    --- Override apply_extmarks to handle both block and inline forms.
    function ref_kind:apply_extmarks(bufnr, lnum, line, ns)
        local priority = self.priority or 1100

        -- Block form: conceal delimiters, highlight name.
        for match_start, name in line:gmatch("()" .. self.pattern) do
            local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, prefix_patterns)
            local col0 = prefix_start - 1
            local open_len = #prefix_text + #open
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
            pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0 + open_len + #name, {
                end_col  = col0 + open_len + #name + #close,
                conceal  = conceal_close,
                hl_group = self.hl_group,
                priority = priority,
            })
        end

        -- Inline form: highlight the whole `@base.sub` token without concealing.
        for match_start, ref in line:gmatch("()@([%w_.%-%+%*%/%\\:]+%.[%w_.%-%+%*%/%\\:]+)") do
            local col0 = match_start - 1
            pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0, {
                end_col  = col0 + 1 + #ref,
                hl_group = self.hl_group,
                priority = priority,
            })
        end
    end

    fluxtags.register_kind(ref_kind)
end

return M
