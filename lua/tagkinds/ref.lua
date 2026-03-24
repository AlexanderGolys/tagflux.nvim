--- @brief [[
--- ref — references to mark tags.
--- @brief ]]

-- @@@fluxtags.ref
-- @##tagkind


local prefixed = require("fluxtags.prefixed_kind")
local kind_common = require("fluxtags.common")
local prefix_util = require("fluxtags.prefix")
local support = require("fluxtags.kind_support")
local Extmark = require("fluxtags.extmark")

local M = {}

--- Iterate inline refs (`@name.sub`) in a single line.
---
---@param line string
---@param cb fun(col0: number, ref: string)
local function for_each_inline_ref(line, cb)
    for match_start, ref in line:gmatch("() @([%w_.%-%+%*%/%\\:]+%.[%w_.%-%+%*%/%\\:]+)") do
        cb(tonumber(match_start) - 1, ref)
    end
end

--- Register the `ref` tag kind with the app.
---
--- Supports both:
--- - block refs: `/@@name`
--- - inline refs: `@name.sub`
---
--- On jump, unresolved refs fall back to diagnostics; valid refs jump to the
--- matching mark (or parent mark for dotted names).
---
---@param fluxtags table
---@return nil
function M.register(fluxtags)
    local runtime = support.new_runtime(fluxtags)
    local marks_cfg = (fluxtags.config.kinds and fluxtags.config.kinds.mark) or {}
    local binder = prefixed.binder(fluxtags, "ref", {
        name = "ref",
        pattern = " /@@([%w_.%-%+%*%/%\\:]+)",
        hl_group = "FluxTagRef",
        conceal_open = "@",
        priority = 1100,
    })
    local kind_cfg = binder.cfg
    local opts = binder.opts

    local open = kind_cfg.open or kind_common.derive_open(opts.pattern, " /@@")
    local marks_kind_name = marks_cfg.name or "mark"
    local ref_diag_ns = fluxtags.utils.make_diag_ns("ref")

    local kind = binder:new_kind({
        name = opts.name,
        pattern = opts.pattern,
        hl_group = opts.hl_group,
        priority = opts.priority,
        save_to_tagfile = false,
        is_valid = kind_common.is_valid_name,
        conceal_pattern = function(name)
            return {
                { offset = 0, length = #open, char = opts.conceal_open },
                { offset = #open, length = #name, hl_group = opts.hl_group },
            }
        end,
        on_jump = function(name, ctx)
            return runtime:jump_to_first(marks_kind_name, name, ctx, "Tag not found: ")
        end,
        apply_extmarks = function(self, bufnr, lnum, line, ns, is_disabled)
            for match_start, name in line:gmatch("()" .. opts.pattern) do
                local prefix_start, prefix_text = prefix_util.find_prefix(line, tonumber(match_start), opts.comment_prefix_patterns)
                local col0 = prefix_start - 1
                local prefix_len = #prefix_text

                if not (is_disabled and is_disabled(lnum, col0)) then
                    Extmark.place(bufnr, ns, lnum, col0, {
                        end_col = col0 + prefix_len + 1,
                        conceal = "/",
                        hl_group = self.hl_group,
                        priority = self.priority or 1100,
                    })
                    Extmark.place(bufnr, ns, lnum, col0 + prefix_len + 1, {
                        end_col = col0 + prefix_len + #open,
                        conceal = "@",
                        hl_group = self.hl_group,
                        priority = self.priority or 1100,
                    })
                    Extmark.place(bufnr, ns, lnum, col0 + prefix_len + #open, {
                        end_col = col0 + prefix_len + #open + #name,
                        hl_group = self.hl_group,
                        priority = self.priority or 1100,
                    })
                end
            end

            for_each_inline_ref(line, function(col0, ref)
                if not (is_disabled and is_disabled(lnum, col0)) then
                    Extmark.place(bufnr, ns, lnum, col0, {
                        end_col = col0 + 1 + #ref,
                        hl_group = self.hl_group,
                        priority = self.priority or 1100,
                    })
                end
            end)
        end,
        apply_diagnostics = function(self, bufnr, lines, is_disabled)
            local tags, diags = fluxtags.utils.load_tagfile(marks_kind_name), {}

            for lnum, line in ipairs(lines) do
                for match_start, name in line:gmatch("()" .. opts.pattern) do
                    local prefix_start, prefix_text = prefix_util.find_prefix(line, tonumber(match_start), opts.comment_prefix_patterns or {})
                    ---@cast prefix_start number
                    ---@cast prefix_text string
                    local col0 = prefix_start - 1
                    local name_col0 = col0 + #prefix_text + #open
                    local name_end = name_col0 + #name

                    if not (is_disabled and is_disabled(lnum - 1, col0)) and (not tags[name] or #tags[name] == 0) then
                        runtime:push_missing_tag_diagnostic({
                            diags = diags,
                            bufnr = bufnr,
                            lnum = lnum - 1,
                            col = name_col0,
                            end_col = name_end,
                            severity = vim.diagnostic.severity.WARN,
                            source = "fluxtags.ref",
                            message_prefix = "Undefined mark: ",
                            name = name,
                        })
                    end
                end

                for_each_inline_ref(line, function(col0, ref)
                    if not (is_disabled and is_disabled(lnum - 1, col0)) then
                        local base_name = ref:match("^([%w_.%-%+%*%/%\\:]+)")
                        if not (tags[ref] and #tags[ref] > 0) and not (tags[base_name] and #tags[base_name] > 0) then
                            runtime:push_missing_tag_diagnostic({
                                diags = diags,
                                bufnr = bufnr,
                                lnum = lnum - 1,
                                col = col0,
                                end_col = col0 + 1 + #ref,
                                severity = vim.diagnostic.severity.WARN,
                                source = "fluxtags.ref",
                                message_prefix = "Undefined mark: ",
                                name = ref,
                            })
                        end
                    end
                end)
            end

            support.publish_diags(bufnr, ref_diag_ns, diags, fluxtags.utils.set_diagnostics)
        end,
    })

    binder:attach_find_at_cursor(kind, kind_common.INLINE_SUBTAG_PATTERN)

    fluxtags.register_kind(kind)
end

return M
