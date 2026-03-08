--- @brief [[
--- mark — named anchor tags.
--- @brief ]]

local prefixed = require("tagkinds.prefixed_kind")
local kind_common = require("fluxtags.common")
local prefix_util = require("fluxtags.prefix")
local jump_util = require("fluxtags.jump")
local diag = require("tagkinds.diagnostics")
local Runtime = require("tagkinds.runtime")

local M = {}

--- Register the `mark` anchor kind.
---
--- Marks are persisted per project and deduplicated at collect/apply time;
--- duplicates produce diagnostics and a jump target via jump resolver.
---
---@param fluxtags table
---@return nil
function M.register(fluxtags)
    local runtime = Runtime.new(fluxtags)
    local binder = prefixed.binder(fluxtags, "mark", {
        name = "mark",
        pattern = " @@@([%w_.%-%+%*/\\:]+)",
        hl_group = "FluxTagMarks",
        open = " @@@",
        conceal_open = "@",
    })
    local opts = binder.opts
    local mark_diag_ns = fluxtags.utils.make_diag_ns("mark")
    local conceal_hl_group = opts.hl_group .. "Conceal"
    local base_hl = vim.api.nvim_get_hl(0, { name = opts.hl_group })
    base_hl.underline = false
    vim.api.nvim_set_hl(0, conceal_hl_group, base_hl)
    local kind = binder:kind_builder({
        save_to_tagfile = true,
        is_valid = kind_common.is_valid_name,
        conceal_pattern = function(name)
            return {
                { offset = 0, length = #opts.open, char = opts.conceal_open, hl_group = conceal_hl_group },
                { offset = #opts.open, length = #name, hl_group = opts.hl_group },
            }
        end,
        on_jump = function(name, ctx)
            return runtime:jump_to_first(ctx.kind_name, name, ctx, "Tag not found: ")
        end,
    })
    function kind:find_at_cursor(line, col)
        local name, s, e = prefix_util.find_tag_at_cursor(line, col, opts.pattern, opts.comment_prefix_patterns)
        if name then
            return name, s, e
        end

        local inline_name, inline_s, inline_e = prefix_util.find_match_at_cursor(line, col, kind_common.INLINE_SUBTAG_PATTERN)
        if inline_name then
            return jump_util.base_name(inline_name), inline_s, inline_e
        end
    end

    binder:attach_prefixed_extmarks(kind, {
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
