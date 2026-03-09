--- @brief [[
--- refog — references to og tags.
--- @brief ]]

-- @@@fluxtags.refog


local prefixed = require("fluxtags.prefixed_kind")
local kind_common = require("fluxtags.common")
local prefix_util = require("fluxtags.prefix")
local support = require("fluxtags.kind_support")

local M = {}

--- Register the `refog` tag kind.
---
--- Reference-only OG syntax that jumps into existing `og` tags and emits
--- warnings when the referenced topic is missing.
---
---@param fluxtags table
---@return nil

function M.register(fluxtags)
    local runtime = support.new_runtime(fluxtags)
    local og_cfg = (fluxtags.config.kinds and fluxtags.config.kinds.og) or {}
    local binder = prefixed.binder(fluxtags, "refog", {
        name = "refog",
        pattern = " #|#||([%w_.%-%+%*%/%\\:]+)||",
        hl_group = "FluxTagRef",
        open = " #|#||",
        close = "||",
        conceal_open = "#",
        conceal_close = "",
    })
    local opts = binder.opts
    local og_kind_name = og_cfg.name or "og"
    local refog_diag_ns = fluxtags.utils.make_diag_ns("refog")

    local kind = binder:new_kind({
        name = opts.name,
        pattern = opts.pattern,
        hl_group = opts.hl_group,
        priority = opts.priority,
        save_to_tagfile = false,
        is_valid = kind_common.is_valid_name,
        conceal_pattern = function(name)
            return {
                { offset = 0, length = #opts.open, char = opts.conceal_open },
                { offset = #opts.open, length = #name, hl_group = opts.hl_group },
                { offset = #opts.open + #name, length = #opts.close, char = opts.conceal_close },
            }
        end,
        on_jump = function(name, ctx)
            return runtime:pick_tag_locations(og_kind_name, name, ctx, "No og tags found: #", "#")
        end,
        apply_diagnostics = function(self, bufnr, lines, is_disabled)
            local tags, diags = fluxtags.utils.load_tagfile(og_kind_name), {}

            for lnum, line in ipairs(lines) do
                for match_start, name in line:gmatch("()" .. opts.pattern) do
                    local prefix_start, prefix_text = prefix_util.find_prefix(line, tonumber(match_start), opts.comment_prefix_patterns or {})
                    ---@cast prefix_start number
                    ---@cast prefix_text string
                    local col0 = prefix_start - 1
                    local name_col0 = col0 + #prefix_text + #opts.open
                    local name_end = name_col0 + #name

                    if not (is_disabled and is_disabled(lnum - 1, col0)) and (not tags[name] or #tags[name] == 0) then
                        runtime:push_missing_tag_diagnostic({
                            diags = diags,
                            bufnr = bufnr,
                            lnum = lnum - 1,
                            col = name_col0,
                            end_col = name_end,
                            severity = vim.diagnostic.severity.WARN,
                            source = "fluxtags.refog",
                            message_prefix = "Undefined og tag: ",
                            name = name,
                        })
                    end
                end
            end

            support.publish_diags(bufnr, refog_diag_ns, diags, fluxtags.utils.set_diagnostics)
        end,
    })

    binder:attach_find_at_cursor(kind)
    binder:attach_prefixed_extmarks(kind, {
        open = opts.open,
        close = opts.close,
        conceal_open = opts.conceal_open,
        conceal_close = opts.conceal_close,
    })

    fluxtags.register_kind(kind)
end

return M
