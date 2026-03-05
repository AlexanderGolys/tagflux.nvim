local M = {}

local descriptions = {
    ft = "Set the buffer filetype (e.g., ft(lua))",
    conceallevel = "Set conceallevel for this buffer (0-3)",
    fluxtags = "Disable all fluxtags processing (off)",
    fluxtags_hl = "Disable highlighting in regions (e.g., fluxtags_hl(off/on))",
    fluxtags_reg = "Disable tag registration in regions (e.g., fluxtags_reg(off/on))",
    modeline = "Execute an arbitrary Ex command",
}

local handlers = {
    ft = function(value, bufnr)
        vim.bo[bufnr].filetype = value
    end,
    conceallevel = function(value, bufnr)
        local level = tonumber(value) or 0
        for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
            if vim.api.nvim_win_is_valid(winid) then
                vim.wo[winid].conceallevel = level
            end
        end
    end,
    fluxtags = function(value, bufnr)
        if value == "off" then
            vim.b[bufnr].fluxtags_disabled = true
        end
    end,
    fluxtags_hl = function() end,
    fluxtags_reg = function() end,
    modeline = function(value, bufnr)
        vim.api.nvim_buf_call(bufnr, function()
            pcall(vim.cmd, value)
        end)
    end,
}

---@return string[]
function M.known_keys()
    local keys = {}
    for key in pairs(handlers) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

---@return {key: string, description: string}[]
function M.info()
    local directives = {}
    for key in pairs(handlers) do
        table.insert(directives, {
            key = key,
            description = descriptions[key] or "No description available",
        })
    end
    table.sort(directives, function(a, b) return a.key < b.key end)
    return directives
end

---@param key string
---@param handler fun(value:string, bufnr:number)
---@param description? string
function M.register(key, handler, description)
    handlers[key] = handler
    if description then descriptions[key] = description end
end

---@param key string
---@return boolean
function M.has(key)
    return handlers[key] ~= nil
end

---@param key string
---@param value string
---@param bufnr number
---@return boolean ok
---@return string? err
function M.exec(key, value, bufnr)
    local handler = handlers[key]
    if not handler then return false, "unknown handler" end
    local ok, err = pcall(handler, value, bufnr)
    return ok, ok and nil or tostring(err)
end

return M
