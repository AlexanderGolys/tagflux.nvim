--- @brief [[
--- refog — references to og tags.
--- @brief ]]

local prefixed = require("tagkinds.prefixed_kind")
local picker_util = require("fluxtags.picker")
local kind_common = require("fluxtags.common")
local diag = require("tagkinds.diagnostics")
local prefix_util = require("fluxtags.prefix")

local M = {}

---@param fluxtags table
function M.register(fluxtags)
    local og_cfg = (fluxtags.config.kinds and fluxtags.config.kinds.og) or {}
    local binder = prefixed.binder(fluxtags, "refog", {
        name = "refog",
        pattern = "#|#||([%w_.%-%+%*%/%\\:]+)||",
        hl_group = "FluxTagRef",
        open = "#|#||",
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
            local tags = ctx.utils.load_tagfile(og_kind_name)
            local entries = tags[name]
            if not entries or #entries == 0 then
                vim.notify("No og tags found: #" .. name, vim.log.levels.WARN)
                return true
            end
            picker_util.pick_locations(entries, "#" .. name, ctx)
            return true
        end,
    })

    binder:attach_find_at_cursor(kind)
    binder:attach_prefixed_extmarks(kind, {
        open = opts.open,
        close = opts.close,
        conceal_open = opts.conceal_open,
        conceal_close = opts.conceal_close,
    })

    function kind:apply_diagnostics(bufnr, lines, is_disabled)
        local tags, diags = fluxtags.utils.load_tagfile(og_kind_name), {}

        for lnum, line in ipairs(lines) do
            for match_start, name in line:gmatch("()" .. opts.pattern) do
                local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, opts.comment_prefix_patterns)
                local col0 = prefix_start - 1
                local name_col0 = col0 + #prefix_text + #opts.open
                local name_end = name_col0 + #name

                if not (is_disabled and is_disabled(lnum - 1, col0)) and (not tags[name] or #tags[name] == 0) then
                    diag.push(
                        diags,
                        bufnr,
                        lnum - 1,
                        name_col0,
                        name_end,
                        vim.diagnostic.severity.WARN,
                        "fluxtags.refog",
                        "Undefined og tag: " .. name
                    )
                end
            end
        end

        diag.publish(bufnr, refog_diag_ns, diags, fluxtags.utils.set_diagnostics)
    end

    fluxtags.register_kind(kind)
end

return M
