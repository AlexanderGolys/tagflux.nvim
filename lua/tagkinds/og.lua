--- @brief [[
--- og — hashtag tags.
--- @brief ]]

-- @@@fluxtags.og
-- @##tagkind

local prefixed = require("fluxtags.prefixed_kind")
local prefix_util = require("fluxtags.prefix")
local kind_common = require("fluxtags.common")
local support = require("fluxtags.kind_support")

local M = {}

--- Register the `og` hashtag tag kind.
---
--- Saved occurrences are available through :FTagsList and `@##name` / hashtag
--- jump flows through `Ctrl-]`.
---
---@param fluxtags table
---@return nil
function M.register(fluxtags)
    local runtime = support.new_runtime(fluxtags)
    local binder = prefixed.binder(fluxtags, "og", {
        name = "og",
        pattern = " @##([%w_%.%-%+%*/%\\:]+)",
        hl_group = "FluxTagOg",
        open = " @##",
        conceal_open = "#",
    })
    local opts = binder.opts

    local kind = binder:new_kind({
        name = opts.name,
        pattern = opts.pattern,
        hl_group = opts.hl_group,
        priority = 1100,
        save_to_tagfile = true,
        is_valid = kind_common.is_valid_name,
        conceal_pattern = function(name)
            return {
                { offset = 0, length = #opts.open, char = opts.conceal_open },
                { offset = #opts.open, length = #name, hl_group = opts.hl_group },
            }
        end,
        on_jump = function(name, ctx)
            return runtime:pick_tag_locations(ctx.kind_name, name, ctx, "No tags found: #", "#")
        end,
        find_at_cursor = function(self, line, col)
            return prefix_util.find_tag_at_cursor(line, col, opts.pattern, opts.comment_prefix_patterns or {})
        end,
        apply_extmarks = function(self, bufnr, lnum, line, ns, is_disabled)
            prefix_util.apply_prefixed_extmarks(bufnr, ns, lnum, line, opts.pattern, opts.comment_prefix_patterns or {}, {
                open = opts.open,
                conceal_open = opts.conceal_open,
                hl_group = self.hl_group,
                priority = self.priority,
            }, is_disabled)
        end,
        collect_tags = function(self, filepath, lines, is_disabled)
            local tags = {}
            for lnum, line in ipairs(lines) do
                for match_start, name in line:gmatch("()" .. opts.pattern) do
                    local prefix_start, prefix_text = prefix_util.find_prefix(line, tonumber(match_start), opts.comment_prefix_patterns or {})
                    ---@cast prefix_start number
                    ---@cast prefix_text string
                    local col0 = prefix_start - 1
                    if not (is_disabled and is_disabled(lnum - 1, col0)) then
                        table.insert(tags, {
                            name = name,
                            file = filepath,
                            lnum = lnum,
                            col = col0 + #prefix_text + #opts.open + 1,
                        })
                    end
                end
            end
            return tags
        end,
    })

    fluxtags.register_kind(kind)
end

return M
