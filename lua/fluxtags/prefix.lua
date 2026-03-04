local M = {}

M.default_comment_prefix_patterns = {
    "%-%-%s*",
    "#+%s*",
    "//%s*",
    ";+%s*",
    "/%*%s*",
    "<!%-%-%s*",
}

--- Find a comment-like prefix that ends immediately before `marker_start`.
--- Returns the 1-indexed start of the prefix and the matched prefix text.
--- When no prefix matches, returns `marker_start` and an empty string.
---
--- @param line string
--- @param marker_start number
--- @param prefix_patterns? string[]
--- @return number
--- @return string
function M.find_prefix(line, marker_start, prefix_patterns)
    local patterns = prefix_patterns or M.default_comment_prefix_patterns
    local before = line:sub(1, marker_start - 1)
    local best_s, best_e = nil, nil

    for _, pattern in ipairs(patterns) do
        local s, e = before:find("(" .. pattern .. ")$")
        if s and e then
            if not best_s or (e - s) > (best_e - best_s) then
                best_s, best_e = s, e
            end
        end
    end

    if best_s and best_e then
        return best_s, before:sub(best_s, best_e)
    end

    return marker_start, ""
end

--- Find a pattern match that overlaps `col`, accounting for optional comment prefixes.
--- Returns the first capture, the prefix-aware start column, and end column (all 1-indexed).
--- Returns nil when no match covers the cursor.
---
---@param line string
---@param col number
---@param pattern string
---@param prefix_patterns? string[]
---@return string|nil
---@return number|nil
---@return number|nil
function M.find_tag_at_cursor(line, col, pattern, prefix_patterns)
    local search_from = 1
    while true do
        local s, e, capture = line:find(pattern, search_from)
        if not s then
            return nil
        end

        local prefix_start = M.find_prefix(line, s, prefix_patterns)
        if col >= prefix_start and col <= e then
            return capture, prefix_start, e
        end

        search_from = e + 1
    end
end

--- Find a pattern match that overlaps `col` without prefix handling.
--- Returns the first capture, start column, and end column (all 1-indexed).
--- Returns nil when no match covers the cursor.
---
---@param line string
---@param col number
---@param pattern string
---@return string|nil
---@return number|nil
---@return number|nil
function M.find_match_at_cursor(line, col, pattern)
    local search_from = 1
    while true do
        local s, e, capture = line:find(pattern, search_from)
        if not s then
            return nil
        end

        if col >= s and col <= e then
            return capture, s, e
        end

        search_from = e + 1
    end
end

--- Apply a common extmark layout for prefixed tags:
--- [comment prefix + open] [name] [optional close].
---
--- @param bufnr number
--- @param ns number
--- @param lnum number
--- @param line string
--- @param pattern string
--- @param prefix_patterns? string[]
--- @param opts table
--- @param is_disabled? fun(lnum: number, col: number): boolean
function M.apply_prefixed_extmarks(bufnr, ns, lnum, line, pattern, prefix_patterns, opts, is_disabled)
    local open = opts.open or ""
    local close = opts.close or ""
    local conceal_open = opts.conceal_open
    local conceal_close = opts.conceal_close
    local open_hl_group = opts.open_hl_group or opts.hl_group
    local name_hl_group = opts.name_hl_group or opts.hl_group
    local close_hl_group = opts.close_hl_group or opts.hl_group
    local priority = opts.priority or 1100

    for match_start, name in line:gmatch("()" .. pattern) do
        local prefix_start, prefix_text = M.find_prefix(line, match_start, prefix_patterns)
        local col0 = prefix_start - 1
        local open_len = #prefix_text + #open

        if not (is_disabled and is_disabled(lnum, col0)) then
            pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0, {
                end_col = col0 + open_len,
                conceal = conceal_open,
                hl_group = open_hl_group,
                priority = priority,
            })

            pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0 + open_len, {
                end_col = col0 + open_len + #name,
                hl_group = name_hl_group,
                priority = priority,
            })

            if close ~= "" or conceal_close ~= nil then
                pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, col0 + open_len + #name, {
                    end_col = col0 + open_len + #name + #close,
                    conceal = conceal_close,
                    hl_group = close_hl_group,
                    priority = priority,
                })
            end
        end
    end
end

return M
