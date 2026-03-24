--- @brief [[
--- mark — named anchor tags.
--- @brief ]]

-- @@@fluxtags.mark
-- @##tagkind

local prefixed = require("fluxtags.prefixed_kind")
local kind_common = require("fluxtags.common")
local prefix_util = require("fluxtags.prefix")
local jump_util = require("fluxtags.jump")
local support = require("fluxtags.kind_support")
local Extmark = require("fluxtags.extmark")

local M = {}

local MARK_NAME_PATTERN = kind_common.NAME_CHARS

---@param name string
---@return string
local function jump_name(name)
    local base = jump_util.base_name(name)
    if base ~= name then
        return base
    end
    return name
end

---@param line string
---@param match_start number
---@return boolean
local function has_valid_mark_boundary(line, match_start)
    return true
end

---@param line string
---@param prefix_patterns string[]
---@param marker_start number
---@param name string
---@param callback fun(prefix_start:number, prefix_text:string)
local function for_each_mark_match(line, prefix_patterns, marker_start, name, callback)
    local prefix_start, prefix_text = prefix_util.find_prefix(line, marker_start, prefix_patterns)
    local has_prefix = prefix_start < marker_start
    if not has_prefix and not has_valid_mark_boundary(line, marker_start) then
        return
    end
    callback(prefix_start, prefix_text)
end

--- Register the `mark` anchor kind.
---
--- Marks are persisted per project and deduplicated at collect/apply time;
--- duplicates produce diagnostics and a jump target via jump resolver.
---
---@param fluxtags table
---@return nil
function M.register(fluxtags)
    local runtime = support.new_runtime(fluxtags)
    local binder = prefixed.binder(fluxtags, "mark", {
        name = "mark",
        pattern = " @@@(" .. MARK_NAME_PATTERN .. ")",
        hl_group = "FluxTagMarks",
        open = " @@@",
        conceal_open = "@",
    })
    local opts = binder.opts
    local mark_diag_ns = fluxtags.utils.make_diag_ns("mark")
    local kind = binder:new_kind({
        name = opts.name,
        pattern = opts.pattern,
        hl_group = opts.hl_group,
        priority = 1100,
        save_to_tagfile = true,
        is_valid = kind_common.is_valid_name,
        conceal_pattern = function(name)
            return {
                { offset = 0, length = #opts.open, char = opts.conceal_open, hl_group = opts.hl_group },
                { offset = #opts.open, length = #name, hl_group = opts.hl_group },
            }
        end,
        on_jump = function(name, ctx)
            return runtime:jump_to_first(ctx.kind_name, jump_name(name), ctx, "Tag not found: ")
        end,
        find_at_cursor = function(self, line, col)
            for match_start, name in line:gmatch("()" .. opts.pattern) do
                local marker_start = tonumber(match_start)
                local prefix_start, prefix_text = prefix_util.find_prefix(line, marker_start, opts.comment_prefix_patterns or {})
                if prefix_start < marker_start or has_valid_mark_boundary(line, marker_start) then
                    local marker_end = marker_start + 2 + #name
                    local start_col = prefix_start
                    if col >= start_col and col <= marker_end then
                        return name, start_col, marker_end
                    end
                end
            end

            local inline_name, inline_s, inline_e = prefix_util.find_match_at_cursor(line, col, kind_common.INLINE_SUBTAG_PATTERN)
            if inline_name then
                return jump_util.base_name(inline_name), inline_s, inline_e
            end
        end,
        apply_extmarks = function(self, bufnr, lnum, line, ns, is_disabled)
            for match_start, name in line:gmatch("()" .. opts.pattern) do
                for_each_mark_match(line, opts.comment_prefix_patterns or {}, tonumber(match_start), name, function(prefix_start, prefix_text)
                    local col0 = prefix_start - 1
                    local open_len = #prefix_text + #opts.open
                    if not (is_disabled and is_disabled(lnum, col0)) then
                        local open_end = col0 + open_len
                        local name_start = open_end
                        local name_end = name_start + #name
                        Extmark.place(bufnr, ns, lnum, col0, {
                            end_col = open_end,
                            conceal = opts.conceal_open,
                            hl_group = self.hl_group,
                            priority = self.priority,
                        })
                        Extmark.place(bufnr, ns, lnum, name_start, {
                            end_col = name_end,
                            hl_group = self.hl_group,
                            priority = self.priority,
                        })
                    end
                end)
            end
        end,
        apply_diagnostics = function(self, bufnr, lines, is_disabled)
            ---@type table<string, {lnum:number, col:number, prefix_len:number}[]>
            local occurrences, diags = {}, {}

            for lnum, line in ipairs(lines) do
                for match_start, name in line:gmatch("()" .. opts.pattern) do
                    for_each_mark_match(line, opts.comment_prefix_patterns or {}, tonumber(match_start), name, function(prefix_start, prefix_text)
                        ---@cast prefix_start number
                        ---@cast prefix_text string
                        occurrences[name] = occurrences[name] or {}
                        table.insert(occurrences[name], {
                            lnum = lnum - 1,
                            col = prefix_start - 1,
                            prefix_len = #prefix_text,
                        })
                    end)
                end
            end
            for name, locs in pairs(occurrences) do
                if #locs > 1 then
                    for _, loc in ipairs(locs) do
                        local name_col0 = loc.col + loc.prefix_len + #opts.open
                        local name_end = name_col0 + #name
                        support.error_extmark(bufnr, fluxtags.utils.ns, loc.lnum, loc.col, name_end, self.priority + 10)
                        support.push_diag(
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
            support.publish_diags(bufnr, mark_diag_ns, diags, fluxtags.utils.set_diagnostics)
        end,
        collect_tags = function(self, filepath, lines, is_disabled)
            local tags = {}

            for lnum, line in ipairs(lines) do
                for match_start, name in line:gmatch("()" .. opts.pattern) do
                    for_each_mark_match(line, opts.comment_prefix_patterns or {}, tonumber(match_start), name, function(prefix_start, prefix_text)
                        local col0 = prefix_start - 1
                        local is_disabled_tag = is_disabled and is_disabled(lnum - 1, col0)
                        if not is_disabled_tag then
                            table.insert(tags, {
                                name = name,
                                file = filepath,
                                lnum = lnum,
                                col = col0 + #prefix_text + #opts.open + 1,
                            })
                        end
                    end)
                end
            end

            return tags
        end,
    })

    fluxtags.register_kind(kind)
end

return M
