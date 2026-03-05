--- @brief [[
--- mark — named anchor tags.
--- @brief ]]

local prefixed = require("tagkinds.prefixed_kind")
local jump_util = require("fluxtags.jump")
local kind_common = require("fluxtags.common")
local prefix_util = require("fluxtags.prefix")
local diag = require("tagkinds.diagnostics")

local M = {}

---@param fluxtags table
function M.register(fluxtags)
    local _, opts = prefixed.resolve(fluxtags, "mark", {
        name = "mark",
        pattern = "@@@([%w_.%-%+%*%/%\\:]+)",
        hl_group = "FluxTagMarks",
        open = "@@@",
        conceal_open = "@",
    })

    local mark_diag_ns = fluxtags.utils.make_diag_ns("mark")
    local conceal_hl_group = opts.hl_group .. "Conceal"
    local base_hl = vim.api.nvim_get_hl(0, { name = opts.hl_group })
    base_hl.underline = false
    vim.api.nvim_set_hl(0, conceal_hl_group, base_hl)

    local kind = prefixed.new_kind({
        name = opts.name,
        pattern = opts.pattern,
        hl_group = opts.hl_group,
        priority = opts.priority,
        save_to_tagfile = true,
        is_valid = kind_common.is_valid_name,
        conceal_pattern = function(name)
            return {
                { offset = 0, length = #opts.open, char = opts.conceal_open, hl_group = conceal_hl_group },
                { offset = #opts.open, length = #name, hl_group = opts.hl_group },
            }
        end,
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

    prefixed.attach_find_at_cursor(kind, opts.pattern, opts.comment_prefix_patterns, kind_common.INLINE_SUBTAG_PATTERN)
    prefixed.attach_prefixed_extmarks(kind, opts.pattern, opts.comment_prefix_patterns, {
        open = opts.open,
        conceal_open = opts.conceal_open,
    })

    function kind:apply_diagnostics(bufnr, lines)
        ---@type table<string, {lnum:number, col:number, prefix_len:number}[]>
        local occurrences, diags = {}, {}

        for lnum, line in ipairs(lines) do
            for match_start, name in line:gmatch("()" .. opts.pattern) do
                if name:match("^[%w_.%-%+%*%/%\\:]+$") then
                    local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, opts.comment_prefix_patterns)
                    occurrences[name] = occurrences[name] or {}
                    table.insert(occurrences[name], {
                        lnum = lnum - 1,
                        col = prefix_start - 1,
                        prefix_len = #prefix_text,
                    })
                end
            end
        end

        for name, locs in pairs(occurrences) do
            if #locs > 1 then
                for _, loc in ipairs(locs) do
                    local name_col0 = loc.col + loc.prefix_len + #opts.open
                    local name_end = name_col0 + #name
                    diag.error_extmark(bufnr, fluxtags.utils.ns, loc.lnum, loc.col, name_end, (self.priority or 1100) + 10)
                    diag.push(
                        diags,
                        bufnr,
                        loc.lnum,
                        name_col0,
                        name_end,
                        vim.diagnostic.severity.ERROR,
                        "fluxtags.mark",
                        "Duplicate mark: " .. name
                    )
                end
            end
        end

        diag.publish(bufnr, mark_diag_ns, diags, fluxtags.utils.set_diagnostics)
    end

    fluxtags.register_kind(kind)
end

return M
