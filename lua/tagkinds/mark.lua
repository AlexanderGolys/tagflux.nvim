--- @brief [[
---     mark — named anchor tags.
---
---     Syntax: `-- @@@<name>`
---     Marks define a named location in a file. They are saved to a tagfile so
---     that `ref` tags and `:FTagsList mark` can navigate to them across sessions.
---     The `-- @@@` prefix is concealed to `@` when conceallevel >= 1.
---
---     Duplicate mark names in the same buffer are highlighted with FluxTagError
---     and emitted as ERROR diagnostics.
--- @brief ]]

-- @@@fluxtags.mark
-- ###tag-kind

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")
local jump_util = require("fluxtags.jump")
local kind_common = require("fluxtags.common")

local M = {}

--- Register the `mark` tag kind with fluxtags.
---
--- Reads per-kind overrides from `fluxtags.config.kinds.mark` so users can
--- customise the pattern, highlight group, or conceal character.
---
--- @param fluxtags table The main fluxtags module table
function M.register(fluxtags)
    local _, opts = kind_common.resolve_kind_config(
        fluxtags,
        "mark",
        {
            name = "mark",
            pattern = "@@@([%w_.%-%+%*%/%\\:]+)",
            hl_group = "FluxTagMarks",
            open = "@@@",
            conceal_open = "@",
        },
        prefix_util.default_comment_prefix_patterns
    )
    local kind_name = opts.name
    local pattern = opts.pattern
    local hl_group = opts.hl_group
    local open = opts.open
    local conceal_open = opts.conceal_open
    local prefix_patterns = opts.comment_prefix_patterns

    --- Create a conceal highlight variant without underline.
    --- This group is used to highlight the concealed `@` character, ensuring it doesn't inherit
    --- underline styling from the base mark highlight group. Useful for users who have underline
    --- set on FluxTagMarks but want clean conceal text.
    local conceal_hl_group = hl_group .. "Conceal"
    local base_hl = vim.api.nvim_get_hl(0, { name = hl_group })
    base_hl.underline = false
    vim.api.nvim_set_hl(0, conceal_hl_group, base_hl)

    --- Diagnostic namespace for mark duplicates.
    --- Used to emit ERROR diagnostics when the same mark name appears multiple times in a buffer.
    local mark_diag_ns = fluxtags.utils.make_diag_ns("mark")

    local kind = tag_kind.new({
        name           = kind_name,
        pattern        = pattern,
        hl_group       = hl_group,
        priority       = opts.priority,
        save_to_tagfile = true,

        is_valid = kind_common.is_valid_name,

        --- Conceal optional comment prefix + `@@@` to a single `@`.
        conceal_pattern = function(name)
            return {
                { offset = 0,      length = #open, char = conceal_open, hl_group = conceal_hl_group },
                { offset = #open,  length = #name, hl_group = hl_group },
            }
        end,

    --- Jump to the mark definition in the tagfile.
    --- For subtags (e.g., @config.defaults), first try the full name,
    --- then fall back to the base name (e.g., @@@config).
    on_jump = function(name, ctx)
        local tags = ctx.utils.load_tagfile(ctx.kind_name)
        local entries, resolved = jump_util.find_entries(tags, name)

        if entries and entries[1] then
            return jump_util.jump_to_entry(name, resolved, entries[1], ctx)
        end

        vim.notify("Tag not found: " .. name, vim.log.levels.WARN)
        return true
        end,
    })

    --- Override find_at_cursor to also detect the inline `@base.sub` form.
    function kind:find_at_cursor(line, col)
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

    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        local priority = self.priority or 1100

        for match_start_raw, name in line:gmatch("()" .. pattern) do
            local match_start = tonumber(match_start_raw)

            if match_start then
                local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, prefix_patterns)
                local col0 = prefix_start - 1
                local open_len = #prefix_text + #open

                local is_disabled_tag = is_disabled and is_disabled(lnum, col0)
                local is_invalid_tag = self.is_valid and not self.is_valid(name)

                if not is_disabled_tag and not is_invalid_tag then
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
        end
    end

    --- Scan all lines, collect duplicate names, apply error extmarks on duplicates.
    function kind:apply_diagnostics(bufnr, lines)
        -- First pass: record every occurrence of each name.
        --- @type table<string, {lnum:number, col:number, prefix_len:number}[]>
        local occurrences = {}
        for lnum, line in ipairs(lines) do
            for match_start_raw, name in line:gmatch("()" .. pattern) do
                if name:match("^[%w_.%-%+%*%/%\\:]+$") then
                    local match_start = tonumber(match_start_raw)

                    if match_start then
                        local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, prefix_patterns)
                        occurrences[name] = occurrences[name] or {}
                        table.insert(occurrences[name], {
                            lnum = lnum - 1,
                            col = prefix_start - 1,
                            prefix_len = #prefix_text,
                        })
                    end
                end
            end
        end

        -- Second pass: emit extmarks and diagnostics for duplicated names.
        local diags = {}
        for name, locs in pairs(occurrences) do
            if #locs > 1 then
                for _, loc in ipairs(locs) do
                    local col0      = loc.col
                    local name_col0 = col0 + loc.prefix_len + #open
                    local name_end  = name_col0 + #name

                    -- Error highlight over the full mark (prefix + name).
                    pcall(vim.api.nvim_buf_set_extmark, bufnr, fluxtags.utils.ns, loc.lnum, col0, {
                        end_col  = name_end,
                        hl_group = "FluxTagError",
                        priority = (self.priority or 1100) + 10,
                    })

                    table.insert(diags, {
                        bufnr    = bufnr,
                        lnum     = loc.lnum,
                        col      = name_col0,
                        end_col  = name_end,
                        severity = vim.diagnostic.severity.ERROR,
                        message  = "Duplicate mark: " .. name,
                        source   = "fluxtags.mark",
                    })
                end
            end
        end

        fluxtags.utils.set_diagnostics(bufnr, mark_diag_ns, diags)
    end

    fluxtags.register_kind(kind)
end

return M
