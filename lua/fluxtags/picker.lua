local M = {}
local Path = require("fluxtags.path")
local path_utils = Path.new()

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
    local ok_telescope, telescope = pcall(require, "telescope.pickers")
    if ok_telescope then
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")
        local previewers = require("telescope.previewers")

        telescope.new({}, {
            prompt_title = title,
            finder = finders.new_table({
                results = entries,
                entry_maker = function(entry)
                    return {
                        value = entry,
                        display = string.format("%s:%d", path_utils:display_relative(entry.file), entry.lnum),
                        ordinal = entry.file .. entry.lnum,
                    }
                end,
            }),
            previewer = previewers.new_buffer_previewer({
                define_preview = function(self, entry)
                    conf.buffer_previewer_maker(entry.value.file, self.state.bufnr, {
                        bufname = self.state.bufname,
                    })
                    vim.api.nvim_buf_call(self.state.bufnr, function()
                        vim.fn.cursor(entry.value.lnum, entry.value.col or 1)
                    end)
                end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    jump_to_entry(selection.value, ctx)
                end)
                return true
            end,
        }):find()
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
        end
    end)
end

return M
