local M = {}

M.NAME_CHARS = "[%w_.%-%+%*%/%\\:]+"
M.INLINE_SUBTAG_PATTERN = "@(" .. M.NAME_CHARS .. "%." .. M.NAME_CHARS .. ")"

---@param name string
---@return boolean
function M.is_valid_name(name)
    return name:match("^" .. M.NAME_CHARS .. "$") ~= nil
end

---@param fluxtags table
---@param kind_name string
---@param defaults table<string, any>
---@param default_prefix_patterns? string[]
---@return table cfg
---@return table resolved
---
function M.resolve_kind_config(fluxtags, kind_name, defaults, default_prefix_patterns)
    local cfg = (fluxtags.config.kinds and fluxtags.config.kinds[kind_name]) or {}
    -- Keep the merge order explicit: runtime config overrides default kind options.
    local resolved = vim.tbl_deep_extend("force", vim.deepcopy(defaults), cfg)

    if default_prefix_patterns then
        resolved.comment_prefix_patterns = cfg.comment_prefix_patterns or default_prefix_patterns
    end

    return cfg, resolved
end

---@param pattern string
---@param fallback string
---@return string
---
function M.derive_open(pattern, fallback)
    -- Pull the literal marker prefix from the pattern (for "/@@...").
    return pattern:match("^(.-)%(%S%+%)") or fallback
end

return M
