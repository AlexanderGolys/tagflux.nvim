local M = {}

---@param name string
---@return string
---
function M.base_name(name)
    return name:match("^([^.]+)") or name
end

---@param tags table<string, table[]>
---@param name string
---@return table[]|nil
---@return string resolved_name
---
function M.find_entries(tags, name)
    local entries = tags[name]
    if entries then
        return entries, name
    end

    local base = M.base_name(name)
    if base ~= name then
        return tags[base], base
    end

    return nil, name
end

---@param search_name string
---@param fallback_name string
---@param entry table
---@param ctx table
---@return boolean
---
function M.jump_to_entry(search_name, fallback_name, entry, ctx)
    ctx.utils.open_file(entry.file, ctx)
    local line = vim.api.nvim_buf_get_lines(0, entry.lnum - 1, entry.lnum, false)[1] or ""
    local col = line:find(search_name, 1, true)

    if not col and fallback_name ~= search_name then
        col = line:find(fallback_name, 1, true)
    end

    vim.fn.cursor(entry.lnum, col or 1)
    return true
end

return M
