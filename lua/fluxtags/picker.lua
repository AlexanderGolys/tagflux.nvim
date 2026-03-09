local M = {}
local Path = require("fluxtags.path")
local path_utils = Path.new()

---@return table|nil
local function snacks_picker()
    if _G.Snacks and _G.Snacks.picker then
        return _G.Snacks.picker
    end
    local ok_snacks, snacks = pcall(require, "snacks")
    if ok_snacks and snacks and snacks.picker then
        return snacks.picker
    end
    return nil
end

---@param entry table
---@param ctx table
local function jump_to_entry(entry, ctx)
    ctx.utils.open_file(entry.file, ctx)
    vim.fn.cursor(entry.lnum, entry.col or 1)
end

---@param entries table[]
---@param title string
---@param ctx table
function M.pick_locations(entries, title, ctx)
    local picker = snacks_picker()
    if picker and picker.select then
        picker.select(entries, {
            title = title,
            format_item = function(entry)
                return string.format("%s:%d", path_utils:display_relative(entry.file), entry.lnum)
            end,
        }, function(choice)
            if choice then
                jump_to_entry(choice, ctx)
            end
        end)
        return
    end

    vim.ui.select(entries, {
        prompt = title,
        format_item = function(entry)
            return string.format("%s:%d", path_utils:display_relative(entry.file), entry.lnum)
        end,
    }, function(choice)
        if choice then
            jump_to_entry(choice, ctx)
        else
            vim.notify("Snacks picker not available", vim.log.levels.WARN)
        end
    end)
end

return M
