--- @brief [[
--- ref — references to mark tags.
--- @brief ]]

local prefixed = require("tagkinds.prefixed_kind")
local jump_util = require("fluxtags.jump")
local kind_common = require("fluxtags.common")
local prefix_util = require("fluxtags.prefix")
local diag = require("tagkinds.diagnostics")

local M = {}

---@param fluxtags table
function M.register(fluxtags)
    local marks_cfg = (fluxtags.config.kinds and fluxtags.config.kinds.mark) or {}
    local cfg, opts = prefixed.resolve(fluxtags, "ref", {
        name = "ref",
        pattern = "/@@([%w_.%-%+%*%/%\\:]+)",
        hl_group = "FluxTagRef",
        conceal_open = "@@",
        priority = 1100,
    })

    local open = cfg.open or kind_common.derive_open(opts.pattern, "/@@")
    local marks_kind_name = marks_cfg.name or "mark"
    local ref_diag_ns = fluxtags.utils.make_diag_ns("ref")

    local kind = prefixed.new_kind({
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
            local tags = ctx.utils.load_tagfile(marks_kind_name)
            local entries, resolved = jump_util.find_entries(tags, name)
            if entries and entries[1] then
                return jump_util.jump_to_entry(name, resolved, entries[1], ctx)
            end
            vim.notify("Tag not found: " .. name, vim.log.levels.WARN)
            return true
        end,
    })

    prefixed.attach_find_at_cursor(kind, opts.pattern, opts.comment_prefix_patterns, kind_common.INLINE_SUBTAG_PATTERN)

    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        prefix_util.apply_prefixed_extmarks(bufnr, ns, lnum, line, opts.pattern, opts.comment_prefix_patterns, {
            open = open,
            conceal_open = opts.conceal_open,
            hl_group = self.hl_group,
            priority = self.priority,
        }, is_disabled)

        for match_start, ref in line:gmatch("()@([%w_.%-%+%*%/%\\:]+%.[%w_.%-%+%*%/%\\:]+)") do
            local col0 = match_start - 1
            if not (is_disabled and is_disabled(lnum, col0)) then
                pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0, {
                    end_col = col0 + 1 + #ref,
                    hl_group = self.hl_group,
                    priority = self.priority or 1100,
                })
            end
        end
    end

    function kind:apply_diagnostics(bufnr, lines, is_disabled)
        local tags, diags = fluxtags.utils.load_tagfile(marks_kind_name), {}

        for lnum, line in ipairs(lines) do
            for match_start, name in line:gmatch("()" .. opts.pattern) do
                local prefix_start, prefix_text = prefix_util.find_prefix(line, match_start, opts.comment_prefix_patterns)
                local col0 = prefix_start - 1
                local name_col0 = col0 + #prefix_text + #open
                local name_end = name_col0 + #name

                if not (is_disabled and is_disabled(lnum - 1, col0)) and (not tags[name] or #tags[name] == 0) then
                    diag.push(
                        diags,
                        bufnr,
                        lnum - 1,
                        name_col0,
                        name_end,
                        vim.diagnostic.severity.WARN,
                        "fluxtags.ref",
                        "Undefined mark: " .. name
                    )
                end
            end

            for match_start, ref in line:gmatch("()@([%w_.%-%+%*%/%\\:]+%.[%w_.%-%+%*%/%\\:]+)") do
                local col0 = match_start - 1
                if not (is_disabled and is_disabled(lnum - 1, col0)) then
                    local base_name = ref:match("^([%w_.%-%+%*%/%\\:]+)")
                    if not (tags[ref] and #tags[ref] > 0) and not (tags[base_name] and #tags[base_name] > 0) then
                        diag.push(
                            diags,
                            bufnr,
                            lnum - 1,
                            col0,
                            col0 + 1 + #ref,
                            vim.diagnostic.severity.WARN,
                            "fluxtags.ref",
                            "Undefined mark: " .. ref
                        )
                    end
                end
            end
        end

        diag.publish(bufnr, ref_diag_ns, diags, fluxtags.utils.set_diagnostics)
    end

    fluxtags.register_kind(kind)
end

return M
