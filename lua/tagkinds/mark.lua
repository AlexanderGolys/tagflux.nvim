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

local M = {}

--- Extract the base name from a possibly-dotted mark (e.g. "config.defaults" -> "config").
--- @param mark_name string
--- @return string
local function base_tag_name(mark_name)
    return mark_name:match("^([^.]+)")
end

--- Register the `mark` tag kind with fluxtags.
---
--- Reads per-kind overrides from `fluxtags.config.kinds.mark` so users can
--- customise the pattern, highlight group, or conceal character.
---
--- @param fluxtags table The main fluxtags module table
function M.register(fluxtags)
    local cfg       = (fluxtags.config.kinds and fluxtags.config.kinds.mark) or {}
    local kind_name = cfg.name      or "mark"
    local pattern   = cfg.pattern   or "@@@([%w_.%-%+%*%/%\\:]+)"
    local hl_group  = cfg.hl_group  or "FluxTagMarks"
    local open      = cfg.open      or "@@@"
    local conceal_open = cfg.conceal_open or "@"
    local prefix_patterns = cfg.comment_prefix_patterns or prefix_util.default_comment_prefix_patterns

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
        priority       = cfg.priority,
        save_to_tagfile = true,

        is_valid = function(name)
            return name:match("^[%w_.%-%+%*%/%\\:]+$") ~= nil
        end,

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
    function kind:find_at_cursor(line, col)
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
            local s, e, mark = line:find("@([%w_.%-%+%*%/%\\:]+%.[%w_.%-%+%*%/%\\:]+)", search_from)
            if not s then return nil end
            if col >= s and col <= e then return mark, s, e end
            search_from = e + 1
        end
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
