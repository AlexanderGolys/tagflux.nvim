local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")
local kind_common = require("fluxtags.common")

local M = {}

---@param fluxtags table
---@param kind_name string
---@param defaults table
---@return table cfg
---@return table opts
function M.resolve(fluxtags, kind_name, defaults)
    return kind_common.resolve_kind_config(
        fluxtags,
        kind_name,
        defaults,
        prefix_util.default_comment_prefix_patterns
    )
end

---@param kind TagKind
---@param pattern string
---@param prefix_patterns string[]
---@param inline_pattern? string
function M.attach_find_at_cursor(kind, pattern, prefix_patterns, inline_pattern)
    function kind:find_at_cursor(line, col)
        local name, s, e = prefix_util.find_tag_at_cursor(line, col, pattern, prefix_patterns)
        if name then return name, s, e end
        if inline_pattern then
            return prefix_util.find_match_at_cursor(line, col, inline_pattern)
        end
        return nil
    end
end

---@param kind TagKind
---@param pattern string
---@param prefix_patterns string[]
---@param ext_opts table
function M.attach_prefixed_extmarks(kind, pattern, prefix_patterns, ext_opts)
    function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
        prefix_util.apply_prefixed_extmarks(
            bufnr,
            ns,
            lnum,
            line,
            pattern,
            prefix_patterns,
            {
                open = ext_opts.open,
                close = ext_opts.close,
                conceal_open = ext_opts.conceal_open,
                conceal_close = ext_opts.conceal_close,
                hl_group = kind.hl_group,
                priority = kind.priority,
            },
            is_disabled
        )
    end
end

---@param opts table
---@return TagKind
function M.new_kind(opts)
    return tag_kind.new(opts)
end

return M
