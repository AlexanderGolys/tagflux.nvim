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

    -- Create a conceal highlight variant without underline
    local conceal_hl_group = hl_group .. "Conceal"
    local base_hl = vim.api.nvim_get_hl(0, { name = hl_group })
    base_hl.underline = false
    vim.api.nvim_set_hl(0, conceal_hl_group, base_hl)

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
    --- Dotted names resolve to their full entry (no base truncation).
    on_jump = function(name, ctx)
        local tags = ctx.utils.load_tagfile(ctx.kind_name)
        if tags[name] and tags[name][1] then
            local entry = tags[name][1]
            ctx.utils.open_file(entry.file, ctx)
            local line = vim.api.nvim_buf_get_lines(0, entry.lnum - 1, entry.lnum, false)[1] or ""
            local col  = line:find(name, 1, true)
            vim.fn.cursor(entry.lnum, col or 1)
            return true
        end
        return false
        end,
    })

    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        local priority = self.priority or 1100

        for match_start, name in line:gmatch("()" .. pattern) do
            local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, prefix_patterns)
            local col0 = prefix_start - 1
            local open_len = #prefix_text + #open

            if is_disabled and is_disabled(lnum, col0) then
                goto continue
            end

            if self.is_valid and not self.is_valid(name) then
                goto continue
            end

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

            ::continue::
        end
    end

    --- Scan all lines, collect duplicate names, apply error extmarks on duplicates.
    function kind:apply_diagnostics(bufnr, lines)
        -- First pass: record every occurrence of each name.
        --- @type table<string, {lnum:number, col:number}[]>
        local occurrences = {}
        for lnum, line in ipairs(lines) do
            for match_start, name in line:gmatch("()" .. pattern) do
                if name:match("^[%w_.%-%+%*%/%\\:]+$") then
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
