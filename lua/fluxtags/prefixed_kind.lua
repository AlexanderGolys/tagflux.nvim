local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")
local kind_common = require("fluxtags.common")

local M = {}

---@class PrefixedKindExtmarkOptions
---@field open? string
---@field close? string
---@field conceal_open? string
---@field conceal_close? string

---@class PrefixedKindBinder
---@field fluxtags table
---@field kind_name string
---@field cfg table
---@field opts table
---@field prefix_patterns string[]
---@field pattern string
local Binder = {}
Binder.__index = Binder

---@param fluxtags table
---@param kind_name string
---@param defaults table
---@return PrefixedKindBinder
function Binder.new(fluxtags, kind_name, defaults)
    local cfg, opts = kind_common.resolve_kind_config(
        fluxtags,
        kind_name,
        defaults,
        prefix_util.default_comment_prefix_patterns
    )
    ---@type PrefixedKindBinder
    local self = setmetatable({
        fluxtags = fluxtags,
        kind_name = kind_name,
        cfg = cfg,
        opts = opts,
        prefix_patterns = opts.comment_prefix_patterns,
        pattern = opts.pattern,
    }, Binder)
    return self
end

--- Return a preconfigured TagKind builder for this binder.
---@param overrides? TagKindOptions
---@return TagKindBuilder
function Binder:kind_builder(overrides)
    local builder = tag_kind.builder({
        name = self.opts.name,
        pattern = self.opts.pattern,
        hl_group = self.opts.hl_group,
        priority = self.opts.priority,
        save_to_tagfile = true,
    })

    if overrides ~= nil then
        builder:with_methods(overrides)
    end

    return builder
end

---@param opts TagKindOptions
---@return TagKind
function Binder:new_kind(opts)
    return self:kind_builder(opts):build()
end

---@param kind TagKind
---@param inline_pattern? string
function Binder:attach_find_at_cursor(kind, inline_pattern)
    local pattern = self.pattern
    local prefix_patterns = self.prefix_patterns
    function kind:find_at_cursor(line, col)
        local name, s, e = prefix_util.find_tag_at_cursor(line, col, pattern, prefix_patterns)
        if name then return name, s, e end
        if inline_pattern then
            return prefix_util.find_match_at_cursor(line, col, inline_pattern)
        end
    end
end

---@param kind TagKind
---@param ext_opts PrefixedKindExtmarkOptions
function Binder:attach_prefixed_extmarks(kind, ext_opts)
    local pattern = self.pattern
    local prefix_patterns = self.prefix_patterns
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

---@param fluxtags table
---@param kind_name string
---@param defaults table
---@return PrefixedKindBinder
function M.binder(fluxtags, kind_name, defaults)
    return Binder.new(fluxtags, kind_name, defaults)
end

---@param fluxtags table
---@param kind_name string
---@param defaults table
---@return PrefixedKindBinder
function M.factory(fluxtags, kind_name, defaults)
    return M.binder(fluxtags, kind_name, defaults)
end

---@param kind TagKind
---@param pattern string
---@param prefix_patterns string[]
---@param inline_pattern? string
function M.attach_find_at_cursor(kind, pattern, prefix_patterns, inline_pattern)
    local binder = setmetatable({
        pattern = pattern,
        prefix_patterns = prefix_patterns,
    }, Binder)
    return binder:attach_find_at_cursor(kind, inline_pattern)
end

---@param kind TagKind
---@param pattern string
---@param prefix_patterns string[]
---@param ext_opts table
function M.attach_prefixed_extmarks(kind, pattern, prefix_patterns, ext_opts)
    local binder = setmetatable({
        pattern = pattern,
        prefix_patterns = prefix_patterns,
    }, Binder)
    return binder:attach_prefixed_extmarks(kind, ext_opts)
end

---@param opts table
---@return TagKind
function M.new_kind(opts)
    return tag_kind.new(opts)
end

return M
